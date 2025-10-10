CREATE DATABASE bestblogs;
USE bestblogs;

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(80) NOT NULL UNIQUE,
    password VARCHAR(120) NOT NULL,
    profile_pic VARCHAR(200),
    INDEX (username)
);

INSERT INTO users (username, password, profile_pic)
VALUES
('admin', 'password123', NULL)