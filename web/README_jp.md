# YouTube Trend Monitor Web

This is a web application that uses the YouTube Data API to perform keyword searches, trend aggregation, CSV export, and email notifications.

- **Backend**: TypeScript / Node.js (`express` + `mongoose`)
- **Frontend**: React + TypeScript + Vite
- **DB**: MongoDB
- **i18n**: Japanese / English / German


## Why this tech stack?

| Technology | Purpose |
|---|---|
| TypeScript | Provides type safety across the frontend and backend. |
| Node.js + Express | Runs the backend and handles API requests. |
| React + Vite | Builds a responsive UI with a fast development workflow. |
| MongoDB + Mongoose | Stores application data in MongoDB using validated models. |


## Features

### Main Screen
- Display YouTube video list in a table by keyword search
- Aggregate and display hit counts for search history and registered keywords in a graph
- Download video list as CSV (date, keyword, video title, URL)


### Settings Screen
- Register/unregister notification email addresses
- Configure SMTP email delivery
- Register monitoring keywords (executed periodically)
- Switch languages (Japanese / English / German)


### Scheduled Execution (Scheduler)
- Search YouTube daily with registered keywords
- Aggregate and save hit counts in the DB
- Email the summary and generated CSV report to addresses registered in Settings


## Setup

### 1. Backend

```powershell
Copy-Item backend\.env.example .env
# Configure the MongoDB URI, encryption key and YouTube API key in .env.
npm install
npm run backend:start
```

The server will start at `http://localhost:8080`.


### 2. Frontend

```powershell
npm run dev
```

Open at `http://localhost:5173`.


## Environment Variables (`.env`)

| Variable | Description |
|------|------|
| `YOUTUBE_API_KEY` | YouTube Data API v3 API key |
| `API_KEY_ENCRYPTION_KEY` | Encryption key for API and SMTP credentials saved from the settings screen (required) |
| `PORT` | Server port (default `8080`) |
| `ACCESS_MONGODB_URI` | MongoDB connection URI including the database name (keep secret; see local JSON fallback below) |
| `CSV_OUTPUT_DIR` | Directory to save periodic search result CSVs for registered keywords (default `./exports`) |
| `SMTP_HOST` | SMTP host for sending notifications |
| `SMTP_PORT` | SMTP port |
| `SMTP_USER` | SMTP user |
| `SMTP_PASS` | SMTP password |
| `SMTP_FROM` | Sender email address |
| `SCHEDULE_CRON` | Aggregation schedule (currently every 24 hours) |


## API Overview

| Method | Path | Description |
|--------|------|------|
| GET | `/api/search?q=xxx&max=25` | YouTube search |
| GET | `/api/search/csv?q=xxx&max=25` | Search result CSV |
| GET | `/api/stats` | Aggregate hit counts for registered keywords |
| GET | `/api/stats/csv` | Download aggregation as CSV |
| GET/POST/DELETE | `/api/keywords` | Manage monitoring keywords |
| GET/POST/DELETE | `/api/emails` | Manage notification email addresses |
| GET/POST | `/api/settings` | Manage settings such as language |
| POST | `/api/run-now` | Run the scheduler immediately |


Register notification email addresses, keywords, and SMTP settings in the Settings screen. SMTP settings can also be provided through the backend `.env` file. The scheduler searches all registered keywords daily, saves video hits to `CSV_OUTPUT_DIR/youtube_hits_YYYY-MM-DD.csv`, and attaches that CSV to the summary email. SMTP passwords saved in Settings are encrypted in the database using `API_KEY_ENCRYPTION_KEY`. The same process can also be executed from "Run Now".

The application starts only after MongoDB and its required indexes are available. Keyword and email IDs are MongoDB ObjectId strings. Existing SQLite data is not imported. Use a stable encryption key across restarts, protect the URI and key as secrets, and monitor MongoDB connection counts and errors as traffic grows.

For local development only, if `ACCESS_MONGODB_URI` is not set in the environment, the backend reads the `ACCESS_MONGODB_URI` string from `backend\src\config\db.json`. This file is ignored by Git and excluded from the container image. Environment variables take precedence; production requires the environment variable. The encryption key still needs to be supplied separately via `.env` or the environment.

## **License**

Free for personal and commercial use.
However, you need to contact the author and developer for commercial use.


### **Support**

If you find this app useful, please consider supporting its development. 
Your support helps maintain and improve the app.

Support: <a href="https://github.com/sponsors/KFrost-Sponsor" rel="noopener noreferrer" style="color: inherit; text-decoration: underline; cursor: pointer;">GitHub Sponsors</a>
