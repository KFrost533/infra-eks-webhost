import nodemailer from 'nodemailer';
import { connectDB, disconnectDB, streamVideoResults } from './db.js';
import { readWeeklyReportConfig, sendWeeklyReport, WeeklyReportError } from './weeklyReport.js';

/** Send the weekly report once and close the MongoDB connection. */
async function main(): Promise<void> {
  let stage = 'configuration';
  try {
    const config = readWeeklyReportConfig(process.env);
    stage = 'database';
    await connectDB({ initialiseIndexes: false });
    const transport = nodemailer.createTransport({
      host: config.host,
      port: 587,
      secure: false,
      requireTLS: true,
      auth: { user: config.user, pass: config.password },
    });
    stage = 'report or delivery';
    await sendWeeklyReport(streamVideoResults(), config, (message) => transport.sendMail(message));
    console.log(`${new Date().toISOString()} sendWeeklyReport: Report accepted by the mail server.`);
  } catch (error) {
    const code = error instanceof WeeklyReportError ? error.code : 'REPORT_FAILED';
    console.error(`${new Date().toISOString()} sendWeeklyReport: Report failed during ${stage} (${code}). Check the job configuration and service health.`);
    process.exitCode = 1;
  } finally {
    try {
      await disconnectDB();
    } catch {
      console.error(`${new Date().toISOString()} sendWeeklyReport: Database disconnect failed.`);
      process.exitCode = 1;
    }
  }
}

await main();
