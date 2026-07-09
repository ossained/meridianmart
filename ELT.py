import io
import os
import logging
import pandas as pd
from datetime import datetime

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

load_dotenv()

OAUTH_CREDENTIALS_FILE = os.getenv("OAUTH_CREDENTIALS_FILE")
TOKEN_FILE = os.getenv("TOKEN_FILE")
SCOPES = [os.getenv("SCOPES")]

FOLDER_SALES = os.getenv("FOLDER_SALES")
FOLDER_REFERENCE = os.getenv("FOLDER_REFERENCE")

TABLE_MAPPING = {
    "Stores_Master":   "ref_store_manager",
    "Staff_Master":    "ref_staff_manager",
    "Managers_Master": "ref_managers",
    "Products_Master": "ref_product_manager",
}

CHUNK_SIZE = 5000


# DB config
def get_env_vars():
    return {
        "DB_USER":     os.getenv("DB_USER"),
        "DB_PASSWORD": os.getenv("DB_PASSWORD"),
        "DB_HOST":     os.getenv("DB_HOST"),
        "DB_PORT":     os.getenv("DB_PORT"),
        "DB_NAME":     os.getenv("DB_NAME"),
    }


def build_engine(config):
    db_url = (
        f"postgresql://{config['DB_USER']}:{config['DB_PASSWORD']}"
        f"@{config['DB_HOST']}:{config['DB_PORT']}/{config['DB_NAME']}"
    )
    return create_engine(db_url, pool_pre_ping=True)


# Authenticate Google Drive
def authenticate_drive():
    creds = None

    if os.path.exists(TOKEN_FILE):
        creds = Credentials.from_authorized_user_file(TOKEN_FILE, SCOPES)

    if not creds or not creds.valid:
        flow = InstalledAppFlow.from_client_secrets_file(OAUTH_CREDENTIALS_FILE, SCOPES)
        creds = flow.run_local_server(port=0)

        with open(TOKEN_FILE, "w") as token:
            token.write(creds.to_json())

    return build("drive", "v3", credentials=creds)


# Fetch files from Drive folder
def fetch_file_list(drive_service, folder_id, label):
    results = drive_service.files().list(
        q=f"'{folder_id}' in parents",
        fields="files(id, name, mimeType)"
    ).execute()

    files = results.get("files", [])
    logging.info(f"Found {len(files)} {label} files.")
    return files


# ⭐ STREAM FILE INTO MEMORY (NO DISK)
def stream_file_to_memory(drive_service, file_id, mime):
    if mime == "application/vnd.google-apps.spreadsheet":
        request = drive_service.files().export_media(
            fileId=file_id,
            mimeType="text/csv"
        )
    else:
        request = drive_service.files().get_media(fileId=file_id)

    buffer = io.BytesIO()
    downloader = MediaIoBaseDownload(buffer, request)

    done = False
    while not done:
        _, done = downloader.next_chunk()

    buffer.seek(0)
    return buffer


# Clean column names
def clean_column_names(columns):
    return (
        columns
        .str.strip()
        .str.lower()
        .str.replace(" ", "_")
        .str.replace(".", "", regex=False)
        .str.replace("(", "", regex=False)
        .str.replace(")", "", regex=False)
    )


# Delete rows previously loaded from this file
def delete_existing_rows_for_file(engine, schema, table, source_file):
    with engine.begin() as conn:
        conn.execute(
            text(f"DELETE FROM {schema}.{table} WHERE source_file = :sf"),
            {"sf": source_file}
        )


# Truncate table
def truncate_table(engine, schema, table):
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE {schema}.{table}"))


# ⭐ STREAM SALES FILES LIVE INTO POSTGRES
def stream_transactions(drive_service, file_list, config):
    engine = build_engine(config)
    total_rows_loaded = 0

    for f in file_list:
        file_id, file_name, mime = f["id"], f["name"], f["mimeType"]

        try:
            logging.info(f"Streaming LIVE: {file_name}")

            delete_existing_rows_for_file(engine, "raw", "transactions", file_name)

            buffer = stream_file_to_memory(drive_service, file_id, mime)

            file_rows = 0
            for chunk in pd.read_csv(buffer, chunksize=CHUNK_SIZE):
                chunk.columns = clean_column_names(chunk.columns)
                chunk["source_file"] = file_name
                chunk["load_timestamp"] = datetime.utcnow().isoformat()

                chunk.to_sql(
                    "transactions",
                    engine,
                    schema="raw",
                    if_exists="append",
                    index=False,
                    method="multi",
                )

                file_rows += len(chunk)

            total_rows_loaded += file_rows
            logging.info(f"Loaded {file_rows} rows from {file_name}")

        except Exception as e:
            logging.error(f"Failed to load {file_name}: {e}")

    logging.info(f"Completed loading {total_rows_loaded} rows into raw.transactions")


# ⭐ STREAM MASTER FILES LIVE INTO POSTGRES
def stream_masters(drive_service, file_list, config):
    engine = build_engine(config)

    for f in file_list:
        file_id, file_name, mime = f["id"], f["name"], f["mimeType"]
        clean_name = file_name.strip()
        table_name = TABLE_MAPPING.get(clean_name)

        if table_name is None:
            logging.warning(f"Skipping unknown file: {clean_name}")
            continue

        try:
            logging.info(f"Streaming LIVE: {file_name}")

            truncate_table(engine, "raw", table_name)

            buffer = stream_file_to_memory(drive_service, file_id, mime)

            file_rows = 0
            for chunk in pd.read_csv(buffer, chunksize=CHUNK_SIZE):
                chunk.to_sql(
                    table_name,
                    engine,
                    schema="raw",
                    if_exists="append",
                    index=False,
                    method="multi",
                )
                file_rows += len(chunk)

            logging.info(f"Loaded {file_rows} rows into raw.{table_name}")

        except Exception as e:
            logging.error(f"Failed to load {file_name}: {e}")

    logging.info("Completed loading all master files")


# Pipeline runner
def run_pipeline():
    logging.info("=" * 50)
    logging.info("STARTING LIVE STREAM ETL PIPELINE")
    logging.info("=" * 50)

    config = get_env_vars()
    drive_service = authenticate_drive()

    sales_files = fetch_file_list(drive_service, FOLDER_SALES, "SALES")
    reference_files = fetch_file_list(drive_service, FOLDER_REFERENCE, "REFERENCE")

    stream_transactions(drive_service, sales_files, config)
    stream_masters(drive_service, reference_files, config)

    logging.info("=" * 50)
    logging.info("PIPELINE COMPLETED")
    logging.info("=" * 50)


if __name__ == "__main__":
    run_pipeline()
