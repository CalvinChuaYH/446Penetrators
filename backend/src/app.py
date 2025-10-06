import os
from flask import Flask
from routes import auth
from flask_cors import CORS
from dotenv import load_dotenv
from flask_sqlalchemy import SQLAlchemy

load_dotenv()
db = SQLAlchemy()

def create_app():
    app = Flask(__name__)
    CORS(app)

    user = os.getenv("DB_USER")
    pw = os.getenv("DB_PASSWORD")
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = os.getenv("DB_PORT", "3306")
    name = os.getenv("DB_NAME")

    app.config["SQLALCHEMY_DATABASE_URI"] = (
        f"mysql+pymysql://{user}:{pw}@{host}/{name}"
    )
    # app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    # app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True, "pool_recycle": 280}

    db.init_app(app)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    return app

app = create_app()
app.register_blueprint(auth, url_prefix='/auth')

if __name__ == '__main__':
    app.run(debug=True)
