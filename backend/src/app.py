import os
from flask import Flask, send_from_directory, request, Response
from routes import auth, user  # Assuming your __init__.py is in 'routes'
from flask_cors import CORS
from dotenv import load_dotenv
from flask_sqlalchemy import SQLAlchemy
import subprocess
import logging  # NEW: For vulnerable logging

load_dotenv()
db = SQLAlchemy()
UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), "uploads")

def create_app():
    app = Flask(__name__)
    CORS(app)

    # NEW: Configure vulnerable logging to /var/log/
    log_handler = logging.FileHandler('/var/log/flaskapp.log')
    log_handler.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s - %(message)s')
    log_handler.setFormatter(formatter)
    app.logger.addHandler(log_handler)
    app.logger.setLevel(logging.INFO)

    db_user = os.getenv("DB_USER")
    pw = os.getenv("DB_PASSWORD")
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = os.getenv("DB_PORT", "3306")
    name = os.getenv("DB_NAME")

    app.config["SQLALCHEMY_DATABASE_URI"] = (
        f"mysql+pymysql://{db_user}:{pw}@{host}/{name}"
    )
    # app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    # app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True, "pool_recycle": 280}

    db.init_app(app)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    @app.route("/uploads/<path:filename>", methods=["GET", "POST", "HEAD"])
    def serve_upload(filename):
        if filename.endswith(".php"):
            fullpath = os.path.join(UPLOAD_FOLDER, filename)
            env = os.environ.copy()
            env.update({
                "REQUEST_METHOD": request.method,
                "SCRIPT_FILENAME": fullpath,
                "SCRIPT_NAME": "/" + filename,
                "REQUEST_URI": request.full_path or request.path,
                "QUERY_STRING": request.query_string.decode() if request.query_string else "",
                "CONTENT_TYPE": request.headers.get("Content-Type", ""),
                "CONTENT_LENGTH": str(len(request.get_data() or b"")),
            })

            try:
                proc = subprocess.run(
                    ["php", "-f", fullpath],           # php-cgi preserves CGI headers
                    input=request.get_data(),              # pass POST body to PHP via stdin
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    timeout=5                             # small timeout for tests
                )
            except subprocess.TimeoutExpired:
                return "PHP execution timed out", 504
            return Response(proc.stdout, mimetype="text/html")
        return send_from_directory(UPLOAD_FOLDER, filename)

    return app

app = create_app()
app.register_blueprint(auth, url_prefix='/auth')
app.register_blueprint(user, url_prefix='/api')

if __name__ == '__main__':
    app.run(debug=True)