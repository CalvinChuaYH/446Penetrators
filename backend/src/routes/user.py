import pymysql
import os
from flask import Blueprint, request, jsonify
from dotenv import load_dotenv
import jwt
from jwt import ExpiredSignatureError, InvalidTokenError

user = Blueprint('user', __name__)

def get_conn():
    load_dotenv()
    user = os.getenv("DB_USER")
    pw = os.getenv("DB_PASSWORD")
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = os.getenv("DB_PORT", "3306")
    name = os.getenv("DB_NAME")

    return pymysql.connect(
        host=host,
        user=user,
        password=pw,   # note: `password` instead of `passwd`
        db=name,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.Cursor   # default cursor, returns tuples
    )

@user.route('/profile', methods=['GET'])
def get_profile():
    auth = request.headers.get('Authorization', None)
    token = None
    if auth:
        parts = auth.split()
        if len(parts) == 2 and parts[0].lower() == 'bearer':
            token = parts[1]
        else:
            return jsonify({"error": "Invalid authorization header"}), 401
    
    if not token:
        return jsonify({"error": "Unauthorized"}), 401
    
    secret = os.getenv("JWT_SECRET")
    try:
        payload = jwt.decode(
            token,
            secret,  
            algorithms=["HS256"],
            options={"require": ["exp", "iat"]} 
        )
    except ExpiredSignatureError as err:
        return jsonify({"error": "Token expired"}), 401
    except InvalidTokenError as err:
        # print("JWT error:", err.__class__.__name__, "-", str(err))
        return jsonify({"error": "Invalid token"}), 401

    # payload now contains verified claims (e.g. sub, email)
    username = payload.get("username")
    profile_pic = payload.get("profile_pic")

    return jsonify({
        "username": username,
        "profile_pic": "http://localhost:5000/uploads/download.jpeg"
    })