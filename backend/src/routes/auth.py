import pymysql
import os
from flask import Blueprint, Flask, request, jsonify
from dotenv import load_dotenv

auth = Blueprint('auth', __name__)

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
            query = f"SELECT * FROM users WHERE username='{request_username}' and password='{request_password}'"
            cur.execute(query)
            row = cur.fetchone()
            if row:
                return jsonify({"message": "Login successful", "token": "fake-jwt-token"}), 200
            return jsonify({"error": "Invalid credentials"}), 401
    finally:
        conn.close()