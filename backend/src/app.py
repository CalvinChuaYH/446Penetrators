import os
from flask import Flask, send_from_directory
from routes import auth, user
from flask_cors import CORS
from dotenv import load_dotenv
from flask_sqlalchemy import SQLAlchemy

load_dotenv()
db = SQLAlchemy()
UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), "uploads")

def create_app():
    app = Flask(__name__)
    CORS(app)

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

    @app.route("/uploads/<path:filename>")
    def serve_upload(filename):
        return send_from_directory(UPLOAD_FOLDER, filename)

    return app

app = create_app()
app.register_blueprint(auth, url_prefix='/auth')
app.register_blueprint(user, url_prefix='/api')

if __name__ == '__main__':
    app.run(debug=True)
