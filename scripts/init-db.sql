-- PostgreSQL initialization script
-- Run once when the database container starts for the first time.
-- Subsequent schema changes are managed by Ecto migrations.

-- Create the test database so CI and local test runs work without a separate setup step
SELECT 'CREATE DATABASE interviewflow_test'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'interviewflow_test')
\gexec

-- Enable extensions in both databases
\c interviewflow_dev
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c interviewflow_test
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
