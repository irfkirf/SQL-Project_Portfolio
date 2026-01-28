-- ====================================================================
-- Bioinformatics BLAST/tBLASTn Pipeline Metadata DB (MySQL 8.0+)
-- Author: Irfan Khan
-- License: MIT (or your preferred license)
-- Created: 2025-09-28
-- ====================================================================
-- USAGE:
--   mysql -u <user> -p < bio_blast_meta_schema.sql
--
-- NOTES:
-- - Safe to run multiple times (CREATE DATABASE IF NOT EXISTS; mostly unique keys).
-- - Views require MySQL 8.0+.
-- - Optional trigger is included but commented out (requires DELIMITER changes).

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Optional safety toggles for repeatable installs
SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;

-- --------------------------------------------------------------------
-- Create Database
-- --------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS bio_blast_meta
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE bio_blast_meta;

-- --------------------------------------------------------------------
-- Access / Governance
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS role (
  role_id       BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(64) NOT NULL UNIQUE,
  description   VARCHAR(255)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS app_user (
  user_id       BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  email         VARCHAR(191) NOT NULL UNIQUE,
  display_name  VARCHAR(128) NOT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS user_role (
  user_id BIGINT UNSIGNED NOT NULL,
  role_id BIGINT UNSIGNED NOT NULL,
  assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, role_id),
  CONSTRAINT fk_user_role_user FOREIGN KEY (user_id) REFERENCES app_user(user_id),
  CONSTRAINT fk_user_role_role FOREIGN KEY (role_id) REFERENCES role(role_id)
) ENGINE=InnoDB;

-- --------------------------------------------------------------------
-- Projects / Samples / Sequences / Files
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project (
  project_id    BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  code          VARCHAR(64) NOT NULL UNIQUE,
  title         VARCHAR(191) NOT NULL,
  description   TEXT,
  owner_user_id BIGINT UNSIGNED,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_project_owner FOREIGN KEY (owner_user_id) REFERENCES app_user(user_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS sample (
  sample_id     BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  project_id    BIGINT UNSIGNED NOT NULL,
  sample_code   VARCHAR(64) NOT NULL,
  organism_note VARCHAR(191),
  collected_on  DATE,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_sample (project_id, sample_code),
  CONSTRAINT fk_sample_project FOREIGN KEY (project_id) REFERENCES project(project_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS file_asset (
  file_id       BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  file_type     ENUM('FASTA','GENBANK','LOG','REPORT','OTHER') NOT NULL,
  uri           VARCHAR(512) NOT NULL,           -- filesystem path or object store URI
  sha256_hex    CHAR(64) NOT NULL,
  byte_size     BIGINT UNSIGNED,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_file_sha (sha256_hex),
  KEY idx_file_type (file_type)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS sequence (
  sequence_id   BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  sample_id     BIGINT UNSIGNED NOT NULL,
  fasta_file_id BIGINT UNSIGNED NOT NULL,
  sequence_name VARCHAR(191) NOT NULL,           -- FASTA header ID
  seq_length    INT UNSIGNED NOT NULL,
  fasta_sha256  CHAR(64) NOT NULL,               -- checksum of the sequence text
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_sequence (sample_id, sequence_name),
  KEY idx_sequence_sample (sample_id),
  CONSTRAINT fk_sequence_sample FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
  CONSTRAINT fk_sequence_file FOREIGN KEY (fasta_file_id) REFERENCES file_asset(file_id)
) ENGINE=InnoDB;

-- --------------------------------------------------------------------
-- Tooling / Parameters
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tool_version (
  tool_version_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  tool_name       VARCHAR(64) NOT NULL,          -- e.g., 'blast+', 'ncbi-blast'
  version_str     VARCHAR(64) NOT NULL,          -- e.g., '2.14.1'
  build_meta      VARCHAR(191),
  UNIQUE KEY uk_tool_version (tool_name, version_str)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS parameter_set (
  parameter_set_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name             VARCHAR(128) NOT NULL,        -- human-friendly label
  program          ENUM('blastn','blastp','tblastn','tblastx','blastx') NOT NULL,
  db_name          VARCHAR(191) NOT NULL,        -- target DB name/alias
  params_json      JSON NOT NULL,                -- full parameter map
  params_hash      CHAR(64) AS (UPPER(SHA2(JSON_PRETTY(params_json), 256))) STORED,
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_param_name (name),
  UNIQUE KEY uk_param_hash (program, db_name, params_hash)
) ENGINE=InnoDB;

-- --------------------------------------------------------------------
-- Runs / Hits / Ranking
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS blast_run (
  blast_run_id     BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  sequence_id      BIGINT UNSIGNED NOT NULL,
  parameter_set_id BIGINT UNSIGNED NOT NULL,
  tool_version_id  BIGINT UNSIGNED NOT NULL,
  status           ENUM('QUEUED','RUNNING','SUCCEEDED','FAILED') NOT NULL DEFAULT 'QUEUED',
  node_host        VARCHAR(128),
  started_at       DATETIME,
  finished_at      DATETIME,
  runtime_sec      INT UNSIGNED GENERATED ALWAYS AS (
                     IF(finished_at IS NULL OR started_at IS NULL, NULL,
                        TIMESTAMPDIFF(SECOND, started_at, finished_at))
                   ) VIRTUAL,
  input_sha256     CHAR(64) NOT NULL,            -- SHA of canonicalized input FASTA for reproducibility
  created_by       BIGINT UNSIGNED,
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_run_sequence (sequence_id, created_at),
  KEY idx_run_status (status),
  CONSTRAINT fk_run_sequence FOREIGN KEY (sequence_id) REFERENCES sequence(sequence_id),
  CONSTRAINT fk_run_param FOREIGN KEY (parameter_set_id) REFERENCES parameter_set(parameter_set_id),
  CONSTRAINT fk_run_tool FOREIGN KEY (tool_version_id) REFERENCES tool_version(tool_version_id),
  CONSTRAINT fk_run_creator FOREIGN KEY (created_by) REFERENCES app_user(user_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS organism (
  organism_id  BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  scientific_name VARCHAR(191) NOT NULL,
  common_name  VARCHAR(191),
  ncbi_taxid   INT UNSIGNED,
  UNIQUE KEY uk_org (scientific_name, COALESCE(ncbi_taxid,0))
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS accession (
  accession_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  accession    VARCHAR(64) NOT NULL,        -- e.g., 'NC_000913.3'
  version      VARCHAR(16),                 -- optional version part
  molecule     ENUM('nucl','prot','other') NOT NULL DEFAULT 'nucl',
  organism_id  BIGINT UNSIGNED,
  UNIQUE KEY uk_accession (accession, COALESCE(version,'')),
  KEY idx_accession_org (organism_id),
  CONSTRAINT fk_accession_org FOREIGN KEY (organism_id) REFERENCES organism(organism_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS hit (
  hit_id        BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  blast_run_id  BIGINT UNSIGNED NOT NULL,
  accession_id  BIGINT UNSIGNED,
  accession_txt VARCHAR(64) NOT NULL,       -- raw accession as reported (for safety)
  subject_desc  VARCHAR(512),
  bit_score     DOUBLE NOT NULL,
  e_value       DOUBLE NOT NULL,
  pct_identity  DECIMAL(6,3) NOT NULL,      -- 0..100
  query_cover   DECIMAL(6,3) NOT NULL,      -- 0..100
  aln_length    INT UNSIGNED,
  hsp_summary   TEXT,                        -- JSON/text summary of HSPs, coords, frames
  rank_key      VARCHAR(64) GENERATED ALWAYS AS (
                 LPAD(CAST(ROUND( -bit_score * 1000 ) AS SIGNED), 8, '0')  -- higher score better
                 ) VIRTUAL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_hit_run (blast_run_id),
  KEY idx_hit_rank (blast_run_id, bit_score DESC, query_cover DESC, e_value ASC),
  KEY idx_hit_accession (accession_id),
  CONSTRAINT fk_hit_run FOREIGN KEY (blast_run_id) REFERENCES blast_run(blast_run_id),
  CONSTRAINT fk_hit_acc FOREIGN KEY (accession_id) REFERENCES accession(accession_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ranked_hit (
  ranked_hit_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  hit_id        BIGINT UNSIGNED NOT NULL,
  blast_run_id  BIGINT UNSIGNED NOT NULL,
  rank_position TINYINT UNSIGNED NOT NULL,   -- 1, 2, or 3
  tie_break_rule VARCHAR(128) NOT NULL,      -- e.g., 'bit_score > cover > e_value'
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_rank_per_run (blast_run_id, rank_position),
  UNIQUE KEY uk_rank_hit (hit_id),
  CONSTRAINT fk_rank_hit FOREIGN KEY (hit_id) REFERENCES hit(hit_id),
  CONSTRAINT fk_rank_run FOREIGN KEY (blast_run_id) REFERENCES blast_run(blast_run_id),
  CONSTRAINT chk_rank_pos CHECK (rank_position IN (1,2,3))
) ENGINE=InnoDB;

-- --------------------------------------------------------------------
-- GenBank Retrieval
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genbank_record (
  genbank_id     BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  accession_id   BIGINT UNSIGNED NOT NULL,
  version        VARCHAR(16),
  features_count INT UNSIGNED,
  locus          VARCHAR(191),
  length_bp      INT UNSIGNED,
  file_id        BIGINT UNSIGNED NOT NULL,     -- links to file_asset row for the .gb/.gbff
  downloaded_at  DATETIME NOT NULL,
  UNIQUE KEY uk_gb (accession_id, COALESCE(version,'')),
  CONSTRAINT fk_gb_accession FOREIGN KEY (accession_id) REFERENCES accession(accession_id),
  CONSTRAINT fk_gb_file FOREIGN KEY (file_id) REFERENCES file_asset(file_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS selected_hit (
  selected_hit_id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  ranked_hit_id   BIGINT UNSIGNED NOT NULL,
  genbank_id      BIGINT UNSIGNED,             -- null until downloaded
  selected_by     BIGINT UNSIGNED,
  selected_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_selected_rank (ranked_hit_id),
  CONSTRAINT fk_sel_rank FOREIGN KEY (ranked_hit_id) REFERENCES ranked_hit(ranked_hit_id),
  CONSTRAINT fk_sel_gb FOREIGN KEY (genbank_id) REFERENCES genbank_record(genbank_id),
  CONSTRAINT fk_sel_user FOREIGN KEY (selected_by) REFERENCES app_user(user_id)
) ENGINE=InnoDB;

-- --------------------------------------------------------------------
-- QC / Audit / Annotations
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS qc_check (
  qc_id        BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  entity_type  ENUM('PROJECT','SAMPLE','SEQUENCE','BLAST_RUN','HIT','GENBANK') NOT NULL,
  entity_id    BIGINT UNSIGNED NOT NULL,
  check_name   VARCHAR(128) NOT NULL,      -- e.g., 'input_checksum_match'
  status       ENUM('PASS','WARN','FAIL') NOT NULL,
  detail       TEXT,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_qc_entity (entity_type, entity_id),
  KEY idx_qc_status (status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS audit_log (
  audit_id     BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id      BIGINT UNSIGNED,
  action       VARCHAR(128) NOT NULL,      -- e.g., 'CREATE_SAMPLE','LAUNCH_RUN'
  entity_type  VARCHAR(64) NOT NULL,
  entity_id    BIGINT UNSIGNED NOT NULL,
  at_time      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  meta         JSON,
  KEY idx_audit_entity (entity_type, entity_id, at_time),
  KEY idx_audit_user (user_id, at_time),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES app_user(user_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tag (
  tag_id     BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name       VARCHAR(64) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tag_map (
  tag_id      BIGINT UNSIGNED NOT NULL,
  entity_type VARCHAR(32) NOT NULL,
  entity_id   BIGINT UNSIGNED NOT NULL,
  tagged_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (tag_id, entity_type, entity_id),
  CONSTRAINT fk_tag_map_tag FOREIGN KEY (tag_id) REFERENCES tag(tag_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS note (
  note_id     BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  entity_type VARCHAR(32) NOT NULL,
  entity_id   BIGINT UNSIGNED NOT NULL,
  author_id   BIGINT UNSIGNED,
  body        TEXT NOT NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_note_entity (entity_type, entity_id, created_at),
  CONSTRAINT fk_note_author FOREIGN KEY (author_id) REFERENCES app_user(user_id)
) ENGINE=InnoDB;

-- --------------------------------------------------------------------
-- Reporting Views
-- --------------------------------------------------------------------
-- Latest successful run for each sequence (by finished_at)
CREATE OR REPLACE VIEW v_latest_run_per_sequence AS
SELECT br.*
FROM blast_run br
JOIN (
  SELECT sequence_id, MAX(finished_at) AS max_finished
  FROM blast_run
  WHERE status = 'SUCCEEDED'
  GROUP BY sequence_id
) t ON t.sequence_id = br.sequence_id AND t.max_finished = br.finished_at;

-- Top 1–3 ranked hits per run with accession/organism context
CREATE OR REPLACE VIEW v_top_hits AS
SELECT
  rh.blast_run_id,
  rh.rank_position,
  h.hit_id,
  h.bit_score,
  h.e_value,
  h.pct_identity,
  h.query_cover,
  a.accession,
  a.version AS accession_version,
  o.scientific_name AS organism
FROM ranked_hit rh
JOIN hit h ON h.hit_id = rh.hit_id
LEFT JOIN accession a ON a.accession_id = h.accession_id
LEFT JOIN organism o ON o.organism_id = a.organism_id
ORDER BY rh.blast_run_id, rh.rank_position;

-- Project-level summary: counts per project
CREATE OR REPLACE VIEW v_project_summary AS
SELECT
  p.project_id,
  p.code,
  p.title,
  COUNT(DISTINCT s.sample_id)    AS samples,
  COUNT(DISTINCT q.sequence_id)  AS sequences,
  COUNT(DISTINCT br.blast_run_id) AS runs,
  SUM(br.status='SUCCEEDED')     AS runs_succeeded,
  SUM(br.status='FAILED')        AS runs_failed
FROM project p
LEFT JOIN sample s  ON s.project_id = p.project_id
LEFT JOIN sequence q ON q.sample_id = s.sample_id
LEFT JOIN blast_run br ON br.sequence_id = q.sequence_id
GROUP BY p.project_id, p.code, p.title;

-- Distribution of selected hits by organism (successful runs only)
CREATE OR REPLACE VIEW v_organism_coverage AS
SELECT
  o.scientific_name AS organism,
  COUNT(*) AS selected_hits
FROM selected_hit sh
JOIN ranked_hit rh ON rh.ranked_hit_id = sh.ranked_hit_id
JOIN hit h ON h.hit_id = rh.hit_id
JOIN blast_run br ON br.blast_run_id = rh.blast_run_id AND br.status='SUCCEEDED'
LEFT JOIN accession a ON a.accession_id = h.accession_id
LEFT JOIN organism o ON o.organism_id = a.organism_id
GROUP BY o.scientific_name
ORDER BY selected_hits DESC;

-- All QC failures with context
CREATE OR REPLACE VIEW v_qc_failures AS
SELECT *
FROM qc_check
WHERE status = 'FAIL'
ORDER BY created_at DESC;

-- --------------------------------------------------------------------
-- Optional Trigger (CONSISTENCY GUARD) - COMMENTED OUT
-- Ensures ranked_hit.blast_run_id matches the hit's blast_run_id
-- --------------------------------------------------------------------
-- DELIMITER //
-- CREATE TRIGGER trg_ranked_hit_consistency
-- BEFORE INSERT ON ranked_hit
-- FOR EACH ROW
-- BEGIN
--   DECLARE v_run BIGINT UNSIGNED;
--   SELECT blast_run_id INTO v_run FROM hit WHERE hit_id = NEW.hit_id;
--   IF v_run IS NULL OR v_run <> NEW.blast_run_id THEN
--     SIGNAL SQLSTATE '45000'
--       SET MESSAGE_TEXT = 'ranked_hit.blast_run_id must match hit.blast_run_id';
--   END IF;
-- END//
-- DELIMITER ;

-- --------------------------------------------------------------------
-- Seed Roles (optional)
-- --------------------------------------------------------------------
INSERT INTO role (name, description) VALUES
  ('admin','Full control'),
  ('analyst','Can view and run reports'),
  ('operator','Can launch pipeline runs')
ON DUPLICATE KEY UPDATE description=VALUES(description);

-- Restore safety toggles
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
