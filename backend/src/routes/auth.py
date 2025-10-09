import pymysql
import os
from flask import Blueprint, Flask, request, jsonify
from dotenv import load_dotenv
import datetime
import jwt
import base64

auth = Blueprint('auth', __name__)
JWT_SECRET = os.getenv("JWT_SECRET")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM")
JWT_EXPIRY = int(os.getenv("JWT_EXPIRY"))

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

@auth.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    request_username = data.get('username')
    request_password = data.get('password')
    if not request_username or not request_password:
        return jsonify({"error": "Username and password required"}), 400
    
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            # YWxpY2UnIE9SICcxJz0nMQ==
            request_username = base64.b64decode(request_username).decode()
            request_password = base64.b64decode(request_password).decode()
            query = f"SELECT * FROM users WHERE username='{request_username}' and password='{request_password}'"
            cur.execute(query)
            row = cur.fetchone()
            print(row)
            if row:
                now = datetime.datetime.now(tz=datetime.timezone.utc)
                exp = now + datetime.timedelta(minutes=JWT_EXPIRY)
                print(f"now: {now}, exp: {exp}")
                payload = {
                    "sub": str(row[1]),              # subject: user id
                    "username": row[1],
                    "profile_pic": row[3],
                    "iat": now,      # issued at
                    "exp": exp,      # expiration
                }
                token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
                return jsonify({"message": "Login successful", "token": token}), 200
            return jsonify({"error": "Invalid credentials"}), 401
    finally:
        conn.close()