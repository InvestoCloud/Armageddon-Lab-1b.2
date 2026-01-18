#!/bin/bash
set -euo pipefail

dnf update -y
dnf install -y python3-pip amazon-cloudwatch-agent
pip3 install flask pymysql boto3

mkdir -p /opt/rdsapp

# 1) Write the app code
cat >/opt/rdsapp/app.py <<'PY'
import json
import os
import boto3
import pymysql
from flask import Flask, request

# Region + sources
REGION = os.environ.get("AWS_REGION", "us-east-1")

# Secrets Manager: credentials only
SECRET_ID = os.environ.get("SECRET_ID", "bmbf-arm4/lab/rds/mysql")

# SSM Parameter Store: non-secret config
SSM_DB_HOST_PARAM = os.environ.get("SSM_DB_HOST_PARAM", "/bmbf_arm_lab/db/host")
SSM_DB_PORT_PARAM = os.environ.get("SSM_DB_PORT_PARAM", "/bmbf_arm_lab/db/port")
SSM_DB_NAME_PARAM = os.environ.get("SSM_DB_NAME_PARAM", "/bmbf_arm_lab/db/name")

secrets = boto3.client("secretsmanager", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)

def log_db_fail(err: Exception, stage: str):
    # This marker string is what we will match later with a CW metric filter.
    print(f"DB_CONNECT_FAIL stage={stage} err={err}", flush=True)

def get_db_creds():
    resp = secrets.get_secret_value(SecretId=SECRET_ID)
    return json.loads(resp["SecretString"])

def get_db_config():
    # SSM returns strings, so port needs int conversion later.
    host = ssm.get_parameter(Name=SSM_DB_HOST_PARAM)["Parameter"]["Value"]
    port = ssm.get_parameter(Name=SSM_DB_PORT_PARAM)["Parameter"]["Value"]
    name = ssm.get_parameter(Name=SSM_DB_NAME_PARAM)["Parameter"]["Value"]
    return host, int(port), name

def ensure_schema():
    c = get_db_creds()
    host, port, dbname = get_db_config()

    try:
        conn = pymysql.connect(
            host=host,
            user=c["username"],
            password=c["password"],
            port=port,
            autocommit=True
        )
        cur = conn.cursor()
        cur.execute(f"CREATE DATABASE IF NOT EXISTS `{dbname}`;")
        cur.execute(f"USE `{dbname}`;")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id INT AUTO_INCREMENT PRIMARY KEY,
                note VARCHAR(255) NOT NULL
            );
        """)
        cur.close()
        conn.close()
    except Exception as e:
        log_db_fail(e, stage="ensure_schema")
        raise

def get_conn():
    c = get_db_creds()
    host, port, dbname = get_db_config()

    try:
        return pymysql.connect(
            host=host,
            user=c["username"],
            password=c["password"],
            port=port,
            database=dbname,
            autocommit=True
        )
    except Exception as e:
        log_db_fail(e, stage="get_conn")
        raise

app = Flask(__name__)

@app.route("/")
def home():
    return """
    <h2>EC2 → RDS Notes App</h2>
    <p><a href="/init">/init</a></p>
    <p><a href="/add?note=hello">/add?note=hello</a></p>
    <p><a href="/list">/list</a></p>
    """

@app.route("/init")
def init_db():
    ensure_schema()
    return "Database initialized."

@app.route("/add")
def add_note():
    note = request.args.get("note", "").strip()
    if not note:
        return "Missing note param", 400
    ensure_schema()
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO notes(note) VALUES(%s);", (note,))
    cur.close()
    conn.close()
    return f"Inserted note: {note}"

@app.route("/list")
def list_notes():
    ensure_schema()
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, note FROM notes ORDER BY id DESC;")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return "<ul>" + "".join(f"<li>{r[0]}: {r[1]}</li>" for r in rows) + "</ul>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
PY

# 2) Create systemd service (writes to /var/log/rdsapp.log)
cat >/etc/systemd/system/rdsapp.service <<'SERVICE'
[Unit]
Description=EC2 to RDS Notes App
After=network.target

[Service]
WorkingDirectory=/opt/rdsapp
Environment=AWS_REGION=us-east-1
Environment=SECRET_ID=bmbf-arm4/lab/rds/mysql
Environment=SSM_DB_HOST_PARAM=/bmbf_arm_lab/db/host
Environment=SSM_DB_PORT_PARAM=/bmbf_arm_lab/db/port
Environment=SSM_DB_NAME_PARAM=/bmbf_arm_lab/db/name

StandardOutput=append:/var/log/rdsapp.log
StandardError=append:/var/log/rdsapp.log

ExecStart=/usr/bin/python3 -u /opt/rdsapp/app.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SERVICE

# 3) Start the app first (so log file exists and receives lines)
systemctl daemon-reload
systemctl enable --now rdsapp

# 4) Now configure CloudWatch Agent (VALID JSON)
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CW'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/rdsapp.log",
            "log_group_name": "/bmbf_arm_lab/app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CW

# 5) Start/Restart agent with this config
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
