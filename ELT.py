"""
ETL Pipeline — Google Drive → PostgreSQL
Run with: python pipeline.py
"""

# Imports
import io
import os
import logging
import pandas as pd
from datetime import datetime
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from sqlalchemy import create_engine
from dotenv import load_dotenv


# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)


# Config

load_dotenv()
SERVICE_ACCOUNT_FILE = os.getenv("SERVICE_ACCOUNT_FILE")
SCOPES = [os.getenv("SCOPES")]  # convert string → list
FOLDER_SALES = os.getenv("FOLDER_SALES")
FOLDER_REFERENCE = os.getenv("FOLDER_REFERENCE")

TABLE_MAPPING = {
    "Stores_Master":   "ref_store_manager",
    "Staff_Master":    "ref_staff_manager",
    "Managers_Master": "ref_managers",
    "Products_Master": "ref_product_manager",
}


# Step 1 — Load environment variables
def get_env_vars() -> dict:
    config = {
        "DB_USER":     os.getenv("DB_USER"),
        "DB_PASSWORD": os.getenv("DB_PASSWORD"),
        "DB_HOST":     os.getenv("DB_HOST"),
        "DB_PORT":     os.getenv("DB_PORT"),
        "DB_NAME":     os.getenv("DB_NAME"),
    }
    return config


# Step 2 — Authenticate Google Drive
def authenticate_drive():
    try:
        creds = service_account.Credentials.from_service_account_file(
            SERVICE_ACCOUNT_FILE, scopes=SCOPES
        )
        drive_service = build("drive", "v3", credentials=creds)
        logging.info("Authenticated with Google Drive successfully.")
        return drive_service

    except Exception as e:
        logging.error(f"Authentication failed: {e}")
        raise


# Step 3 — Fetch file lists from Drive folders
def fetch_file_list(drive_service, folder_id: str, label: str) -> list:
    try:
        results = drive_service.files().list(
            q=f"'{folder_id}' in parents",
            fields="files(id, name, mimeType)"
        ).execute()

        files = results.get("files", [])

        if not files:
            logging.warning(f"No {label} files found in folder: {folder_id}")

        logging.info(f"Found {len(files)} {label} files.")
        return files

    except Exception as e:
        logging.error(f"Failed to fetch {label} file list: {e}")
        raise


# Step 4 — Download files into memory
def download_files(drive_service, file_list: list, label: str) -> dict:
    dataframes = {}

    for f in file_list:
        file_id   = f["id"]
        file_name = f["name"]
        mime      = f["mimeType"]

        try:
            logging.info(f"Processing: {file_name} | Type: {mime}")

            if mime == "application/vnd.google-apps.spreadsheet":
                request = drive_service.files().export_media(
                    fileId=file_id,
                    mimeType="text/csv"
                )
            else:
                request = drive_service.files().get_media(fileId=file_id)

            file_stream = io.BytesIO()
            downloader  = MediaIoBaseDownload(file_stream, request)

            done = False
            while not done:
                _, done = downloader.next_chunk()

            file_stream.seek(0)
            df = pd.read_csv(file_stream)
            dataframes[file_name] = df
            logging.info(f"Loaded: {file_name} ({len(df)} rows)")

        except Exception as e:
            logging.error(f"Failed to load {file_name}: {e}")
            continue

    logging.info(f"All {label} files loaded into memory. ({len(dataframes)} total)")
    return dataframes


# Step 5a — Load sales files → raw.transactions
def load_transactions(dataframes: dict, config: dict) -> None:
    try:
        db_url = (
            f"postgresql://{config['DB_USER']}:{config['DB_PASSWORD']}"
            f"@{config['DB_HOST']}:{config['DB_PORT']}/{config['DB_NAME']}"
        )
        engine = create_engine(db_url)

        dfs = []
        for name, df in dataframes.items():
            df = df.copy()
            df["source_file"] = name
            dfs.append(df)
            logging.info(f"Queued: {name} ({len(df)} rows)")

        combined_df = pd.concat(dfs, ignore_index=True)
        logging.info(f"Combined: {len(combined_df)} total rows, {len(combined_df.columns)} columns")

        combined_df.columns = (
            combined_df.columns
            .str.strip()
            .str.lower()
            .str.replace(" ", "_")
            .str.replace(".", "", regex=False)
            .str.replace("(", "", regex=False)
            .str.replace(")", "", regex=False)
        )

        combined_df["load_timestamp"] = datetime.utcnow().isoformat()

        combined_df.to_sql(
            "transactions",
            engine,
            schema="raw",
            if_exists="append",
            index=False
        )
        logging.info(f"raw.transactions loaded with {len(combined_df)} rows.")

    except Exception as e:
        logging.error(f"Failed to load raw.transactions: {e}")
        raise


# Step 5b — Load master files → raw.ref_* tables
def load_masters(dataframes: dict, config: dict) -> None:
    try:
        db_url = (
            f"postgresql://{config['DB_USER']}:{config['DB_PASSWORD']}"
            f"@{config['DB_HOST']}:{config['DB_PORT']}/{config['DB_NAME']}"
        )
        engine = create_engine(db_url)

        for name, df in dataframes.items():
            clean_name = name.strip()
            table_name = TABLE_MAPPING.get(clean_name)

            if table_name is None:
                logging.warning(f"Skipping unknown file: '{clean_name}'")
                continue

            try:
                df = df.copy()
                df.to_sql(
                    table_name,
                    engine,
                    schema="raw",
                    if_exists="append",
                    index=False
                )
                logging.info(f"raw.{table_name} loaded with {len(df)} rows.")

            except Exception as e:
                logging.error(f"Failed to load raw.{table_name}: {e}")
                continue

        logging.info("All master tables loaded successfully.")

    except Exception as e:
        logging.error(f"Database connection failed: {e}")
        raise


# Pipeline — orchestrates all steps
def run_pipeline() -> None:
    logging.info("=" * 50)
    logging.info("         STARTING ETL PIPELINE")
    logging.info("=" * 50)

    logging.info("[1/5] Loading environment variables...")
    config = get_env_vars()

    logging.info("[2/5] Authenticating with Google Drive...")
    drive_service = authenticate_drive()

    logging.info("[3/5] Fetching file lists from Drive...")
    sales_files     = fetch_file_list(drive_service, FOLDER_SALES,     label="SALES")
    reference_files = fetch_file_list(drive_service, FOLDER_REFERENCE, label="REFERENCE")

    logging.info("[4/5] Downloading files into memory...")
    all_dataframes       = download_files(drive_service, sales_files,     label="SALES")
    reference_dataframes = download_files(drive_service, reference_files, label="REFERENCE")

    logging.info("[5/5] Loading into PostgreSQL...")
    load_transactions(all_dataframes,       config)
    load_masters(reference_dataframes, config)

    logging.info("=" * 50)
    logging.info("    PIPELINE COMPLETED SUCCESSFULLY")
    logging.info("=" * 50)


# Entry point
if __name__ == "__main__":
    run_pipeline()
