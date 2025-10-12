import pymysql
import os
from flask import Blueprint, request, jsonify
from dotenv import load_dotenv
import jwt
from jwt import ExpiredSignatureError, InvalidTokenError
from werkzeug.utils import secure_filename

user = Blueprint('user', __name__)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPLOAD_FOLDER = os.path.join(BASE_DIR, "uploads")  

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

# NEW: Helper function to decode JWT (reuse in both routes)
def decode_jwt(token):
    secret = os.getenv("JWT_SECRET")
    try:
        payload = jwt.decode(
            token,
            secret,  
            algorithms=["HS256"],
            options={"require": ["exp", "iat"]} 
        )
        return payload
    except (ExpiredSignatureError, InvalidTokenError) as err:
        raise ValueError("Invalid or expired token")

# NEW: Vulnerable endpoint - any auth user can read logs
@user.route('/logs', methods=['GET'])
def read_logs():
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
    
    try:
        payload = decode_jwt(token)
    except ValueError as err:
        return jsonify({"error": str(err)}), 401

    # VULN: Read and return entire log file (possible via adm group)
    try:
        with open('/var/log/flaskapp.log', 'r') as f:
            logs = f.read()
        return jsonify({'logs': logs}), 200
    except Exception as e:
        return jsonify({'error': f'Failed to read logs: {str(e)}'}), 500

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
    
    try:
        payload = decode_jwt(token)  # Reuse helper
    except ValueError as err:
        return jsonify({"error": str(err)}), 401

    # payload now contains verified claims (e.g. sub, email)
    username = payload.get("username")

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT profile_pic FROM users WHERE username = %s", (username,))
            row = cur.fetchone()   # default cursor returns a tuple
    finally:
        conn.close()
    profile_pic = row[0] if row and row[0] else None
    profile_pic = f"http://localhost:5000/uploads/{profile_pic}" if profile_pic else None

    return jsonify({
        "username": username,
        "profile_pic": profile_pic
    }), 200

@user.route('/upload', methods=['POST'])
def update_profile_pic():
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
    
    try:
        payload = decode_jwt(token)  # Reuse helper
    except ValueError as err:
        return jsonify({"error": str(err)}), 401

    username = payload.get("username")
    file = request.files.get('profile_pic')
    if not file:
        return jsonify({"error": "No file uploaded"}), 400
    
    file_type = file.content_type
    print(file_type)
    if file_type not in ['image/png', 'image/jpeg']:
        return jsonify({"error": "Invalid file type. Only PNG and JPEG are allowed."}), 400
    
    filename = secure_filename(file.filename)
    save_path = os.path.join(UPLOAD_FOLDER, filename)
    file.save(save_path)

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            query = f"UPDATE users SET profile_pic='{filename}' WHERE username='{username}'"
            cur.execute(query)
            conn.commit()
    finally:
        conn.close()

    return jsonify({"message": f"Profile picture uploaded to /uploads/{filename}", "profile_pic": f"http://localhost:5000/uploads/{filename}"}), 200