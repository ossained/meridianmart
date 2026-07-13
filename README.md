# MeridianMart Retail Data Warehouse & ELT Pipeline

## Overview

MeridianMart is a fictional retail chain operating **11 stores across three regions**. Each store records sales using Google Forms, resulting in separate Google Sheets with inconsistent data structures and no centralized reporting.

This project demonstrates how to design and implement a complete **ELT (Extract, Load, Transform)** data warehouse using **Python, PostgreSQL, and SQL**. The solution consolidates transactional and reference data into a centralized warehouse, validates data quality, models a star schema, and produces reporting-ready datasets.

---

## Business Problem

As MeridianMart expanded, each branch independently managed its sales records using Google Forms and Google Sheets.

This created several business challenges:

- Data stored across 11 independent spreadsheets
- No centralized reporting
- Inconsistent product and staff names
- No data validation during data entry
- Difficult regional performance analysis
- Time-consuming manual reconciliation

The objective of this project is to build a scalable data warehouse that transforms fragmented operational data into a single source of truth for business reporting.

---

## Project Objectives

- Extract data from 11 Google Sheets and 4 master reference sheets
- Load raw data into PostgreSQL without modification
- Validate and clean data using SQL
- Build a dimensional star schema
- Generate business reporting tables
- Automate the entire pipeline using Python

---

# Architecture

```
Google Forms
      │
      ▼
Google Sheets (15 Sheets)
      │
      ▼
Python ETL (Google Sheets API)
      │
      ▼
PostgreSQL
│
├── Raw Schema
│
├── Staging Schema
│
├── Data Mart
│      ├── Fact Table
│      └── Dimension Tables
│
└── Reporting Schema
```

---

# Technology Stack

| Technology | Purpose |
|------------|---------|
| Python | Data extraction and orchestration |
| Google Sheets API | Source system extraction |
| SQLAlchemy | Database connection |
| PostgreSQL | Data warehouse |
| SQL | Data transformation |
| Cron | Pipeline scheduling |
| Git | Version control |

---

# Data Sources

The pipeline extracts data from:

### Transaction Sources

- Store 1 Sales
- Store 2 Sales
- Store 3 Sales
- Store 4 Sales
- Store 5 Sales
- Store 6 Sales
- Store 7 Sales
- Store 8 Sales
- Store 9 Sales
- Store 10 Sales
- Store 11 Sales

### Reference Data

- Product Master
- Staff Master
- Manager Master
- Store Master

---

# Data Warehouse Structure

```
PostgreSQL
│
├── raw
│     ├── sales_store_01
│     ├── sales_store_02
│     ├── ...
│     ├── products
│     ├── staff
│     ├── managers
│     └── stores
│
├── staging
│
├── marts
│     ├── fact_transactions
│     ├── dim_products
│     ├── dim_staff
│     ├── dim_managers
│     ├── dim_stores
│     └── dim_date
│
├── reporting
│
└── audit
```

---

# Star Schema

## Fact Table

- fact_transactions

## Dimension Tables

- dim_products
- dim_staff
- dim_managers
- dim_stores
- dim_date

Relationship

```
                dim_products
                     │
                     │
dim_staff ─── fact_transactions ─── dim_stores
                     │
                     │
                 dim_date

dim_managers
      │
      └──────────► dim_products
```

---

# ELT Pipeline

## Step 1 – Extract

Python connects to the Google Sheets API and extracts all sales and master data.

## Step 2 – Load

Data is loaded directly into the PostgreSQL **raw** schema without modification.

## Step 3 – Validate

SQL scripts perform validation checks including:

- NULL values
- Invalid payment methods
- Duplicate receipts
- Invalid quantities
- Missing product references
- Missing staff references
- Missing store references

Validation results are logged into:

```
audit.validation_log
```

## Step 4 – Transform

SQL transforms validated data into a dimensional star schema by:

- Resolving product prices
- Calculating sales totals
- Assigning surrogate keys
- Building dimensions
- Loading the fact table

## Step 5 – Reporting

Reporting tables are generated for business users including:

- Daily Sales
- Regional Sales
- Store Performance
- Top Selling Products
- Payment Method Analysis

---

# Data Quality Rules

The staging layer enforces:

- NOT NULL constraints
- CHECK constraints
- Foreign key constraints
- Duplicate detection
- Referential integrity
- Product lookup validation
- Staff lookup validation
- Store lookup validation

---

# Project Folder Structure

```
MeridianMart-DataWarehouse/
│
├── data/
│
├── sql/
│   ├── raw/
│   ├── staging/
│   ├── marts/
│   ├── reporting/
│   └── validation/
│
├── python/
│   ├── extract.py
│   ├── load.py
│   ├── transform.py
│   └── runner.py
│
├── docs/
│   ├── ERD.png
│   ├── pipeline_reference.md
│   └── architecture.png
│
├── README.md
│
└── requirements.txt
```

---

# Reporting Outputs

The warehouse supports analytics such as:

- Daily revenue by store
- Regional sales performance
- Product category analysis
- Top-selling products
- Cash vs Card vs Transfer payments
- Staff sales performance
- Store comparison
- Sales trends over time

---

# Key Features

- Automated ELT pipeline
- Centralized PostgreSQL warehouse
- SQL-based data transformation
- Star schema dimensional model
- Data validation framework
- Audit logging
- Reporting-ready data marts
- Scalable architecture

---


---

# Skills Demonstrated

- Data Engineering
- Data Warehousing
- PostgreSQL
- SQL Development
- Python Programming
- ETL/ELT Pipeline Design
- Data Modeling
- Star Schema Design
- Data Validation
- Dimensional Modeling
- Git & GitHub
- Business Intelligence

---

# Author

**Ossai Chukwunedum**

Data Engineer 
