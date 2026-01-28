# Usage Examples

This document provides practical SQL examples for common workflows in the Bioinformatics BLAST Pipeline Metadata System.

## Table of Contents
1. [Project Management](#project-management)
2. [Sample & Sequence Workflows](#sample--sequence-workflows)
3. [BLAST Run Operations](#blast-run-operations)
4. [Result Analysis](#result-analysis)
5. [Quality Control](#quality-control)
6. [Reporting & Analytics](#reporting--analytics)
7. [Data Export](#data-export)

## Project Management

### Create a New Project

```sql
-- Create project with owner
INSERT INTO project (code, title, description, owner_user_id)
VALUES (
  'MARINE2025',
  'Marine Microbiome Diversity Study',
  'Characterization of microbial communities in coastal waters',
  1  -- user_id of project owner
);

-- Log the action
INSERT INTO audit_log (user_id, action, entity_type, entity_id, meta)
VALUES (
  1,
  'CREATE_PROJECT',
  'PROJECT',
  LAST_INSERT_ID(),
  JSON_OBJECT('source', 'manual_creation')
);
```

### List All Projects with Statistics

```sql
-- Using the pre-built view
SELECT 
  code,
  title,
  samples,
  sequences,
  runs,
  runs_succeeded,
  runs_failed,
  ROUND(100.0 * runs_succeeded / NULLIF(runs, 0), 2) AS success_rate
FROM v_project_summary
ORDER BY runs_succeeded DESC;
```

### Find Projects by Owner

```sql
SELECT 
  p.code,
  p.title,
  u.display_name AS owner,
  u.email,
  p.created_at
FROM project p
JOIN app_user u ON u.user_id = p.owner_user_id
WHERE u.email = 'researcher@example.com';
```

## Sample & Sequence Workflows

### Batch Import Samples

```sql
-- Import multiple samples for a project
INSERT INTO sample (project_id, sample_code, organism_note, collected_on)
VALUES
  (1, 'SITE_A_001', 'Coastal seawater - 5m depth', '2025-01-15'),
  (1, 'SITE_A_002', 'Coastal seawater - 10m depth', '2025-01-15'),
  (1, 'SITE_B_001', 'Offshore seawater - 5m depth', '2025-01-16'),
  (1, 'SITE_B_002', 'Offshore seawater - 10m depth', '2025-01-16');

-- Add tags to samples
INSERT INTO tag (name) VALUES ('coastal'), ('offshore')
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- Tag coastal samples
INSERT INTO tag_map (tag_id, entity_type, entity_id)
SELECT t.tag_id, 'SAMPLE', s.sample_id
FROM sample s
JOIN tag t ON t.name = 'coastal'
WHERE s.sample_code LIKE 'SITE_A%';
```

### Register FASTA File and Sequences

```sql
-- Register the FASTA file
INSERT INTO file_asset (file_type, uri, sha256_hex, byte_size)
VALUES (
  'FASTA',
  '/data/projects/MARINE2025/SITE_A_001.fasta',
  SHA2(LOAD_FILE('/data/projects/MARINE2025/SITE_A_001.fasta'), 256),
  123456
);

SET @fasta_file_id = LAST_INSERT_ID();

-- Register sequences from the file
INSERT INTO sequence (sample_id, fasta_file_id, sequence_name, seq_length, fasta_sha256)
VALUES
  (1, @fasta_file_id, 'contig_001', 2458, SHA2('ATCG...', 256)),
  (1, @fasta_file_id, 'contig_002', 1834, SHA2('GCTA...', 256)),
  (1, @fasta_file_id, 'contig_003', 3921, SHA2('TAGC...', 256));
```

### Find Sequences by Criteria

```sql
-- Find sequences longer than 2000 bp
SELECT 
  p.code AS project,
  s.sample_code AS sample,
  q.sequence_name,
  q.seq_length,
  q.created_at
FROM sequence q
JOIN sample s ON s.sample_id = q.sample_id
JOIN project p ON p.project_id = s.project_id
WHERE q.seq_length > 2000
ORDER BY q.seq_length DESC;
```

## BLAST Run Operations

### Create Parameter Sets

```sql
-- tBLASTn against nr database
INSERT INTO parameter_set (name, program, db_name, params_json)
VALUES (
  'Standard tBLASTn - NR',
  'tblastn',
  'nr',
  JSON_OBJECT(
    'evalue', 1e-5,
    'max_target_seqs', 100,
    'word_size', 3,
    'matrix', 'BLOSUM62',
    'seg', 'yes',
    'comp_based_stats', 2
  )
);

-- BLASTn for highly similar sequences
INSERT INTO parameter_set (name, program, db_name, params_json)
VALUES (
  'High Identity BLASTn - NT',
  'blastn',
  'nt',
  JSON_OBJECT(
    'evalue', 1e-10,
    'perc_identity', 95.0,
    'max_target_seqs', 50,
    'word_size', 11,
    'dust', 'yes'
  )
);
```

### Launch BLAST Runs

```sql
-- Queue runs for all sequences in a project
INSERT INTO blast_run (
  sequence_id,
  parameter_set_id,
  tool_version_id,
  status,
  input_sha256,
  created_by
)
SELECT 
  q.sequence_id,
  1,  -- parameter_set_id for 'Standard tBLASTn - NR'
  1,  -- tool_version_id for BLAST+ 2.14.1
  'QUEUED',
  q.fasta_sha256,
  1   -- user_id of requester
FROM sequence q
JOIN sample s ON s.sample_id = q.sample_id
WHERE s.project_id = 1;
```

### Update Run Status

```sql
-- Mark run as started
UPDATE blast_run
SET 
  status = 'RUNNING',
  started_at = NOW(),
  node_host = 'compute-node-05'
WHERE blast_run_id = 42;

-- Mark run as completed successfully
UPDATE blast_run
SET 
  status = 'SUCCEEDED',
  finished_at = NOW()
WHERE blast_run_id = 42;

-- Mark run as failed with QC check
UPDATE blast_run
SET 
  status = 'FAILED',
  finished_at = NOW()
WHERE blast_run_id = 43;

INSERT INTO qc_check (entity_type, entity_id, check_name, status, detail)
VALUES (
  'BLAST_RUN',
  43,
  'output_validation',
  'FAIL',
  'No significant hits found; possible input quality issue'
);
```

### Monitor Run Queue

```sql
-- Check queue status
SELECT 
  status,
  COUNT(*) AS count,
  MIN(created_at) AS oldest,
  MAX(created_at) AS newest
FROM blast_run
GROUP BY status;

-- Find long-running jobs
SELECT 
  blast_run_id,
  sequence_id,
  node_host,
  started_at,
  TIMESTAMPDIFF(MINUTE, started_at, NOW()) AS running_minutes
FROM blast_run
WHERE status = 'RUNNING'
  AND TIMESTAMPDIFF(MINUTE, started_at, NOW()) > 60
ORDER BY running_minutes DESC;
```

## Result Analysis

### Insert BLAST Hits

```sql
-- Insert hits for a successful run
INSERT INTO hit (
  blast_run_id,
  accession_txt,
  subject_desc,
  bit_score,
  e_value,
  pct_identity,
  query_cover,
  aln_length,
  hsp_summary
)
VALUES
  (
    42,
    'WP_012345678.1',
    'hypothetical protein [Escherichia coli]',
    450.2,
    1e-125,
    87.5,
    95.2,
    256,
    JSON_OBJECT('qstart', 1, 'qend', 256, 'sstart', 50, 'send', 305)
  ),
  (
    42,
    'WP_087654321.1',
    'DNA helicase [Pseudomonas aeruginosa]',
    398.7,
    3e-110,
    82.3,
    89.1,
    234,
    JSON_OBJECT('qstart', 12, 'qend', 245, 'sstart', 100, 'send', 333)
  );
```

### Rank Top Hits

```sql
-- Automatically rank top 3 hits per run
INSERT INTO ranked_hit (blast_run_id, hit_id, rank_position)
SELECT 
  blast_run_id,
  hit_id,
  ROW_NUMBER() OVER (PARTITION BY blast_run_id ORDER BY bit_score DESC) AS rank_position
FROM hit
WHERE blast_run_id = 42
LIMIT 3;
```

### Query Top Hits with Context

```sql
-- Get top hits for a specific sequence
SELECT 
  s.sequence_name,
  rh.rank_position,
  h.accession_txt,
  h.subject_desc,
  h.bit_score,
  h.e_value,
  h.pct_identity,
  h.query_cover,
  o.scientific_name AS organism
FROM sequence s
JOIN blast_run br ON br.sequence_id = s.sequence_id
JOIN ranked_hit rh ON rh.blast_run_id = br.blast_run_id
JOIN hit h ON h.hit_id = rh.hit_id
LEFT JOIN accession a ON a.accession_id = h.accession_id
LEFT JOIN organism o ON o.organism_id = a.organism_id
WHERE s.sequence_name = 'contig_001'
  AND br.status = 'SUCCEEDED'
ORDER BY rh.rank_position;
```

### Find Best Hits Across Multiple Runs

```sql
-- For each sequence, find the best hit ever recorded
SELECT 
  q.sequence_name,
  h.accession_txt,
  h.subject_desc,
  MAX(h.bit_score) AS best_bit_score,
  MIN(h.e_value) AS best_e_value,
  MAX(h.pct_identity) AS best_identity
FROM sequence q
JOIN blast_run br ON br.sequence_id = q.sequence_id
JOIN hit h ON h.blast_run_id = br.blast_run_id
WHERE br.status = 'SUCCEEDED'
  AND q.sample_id IN (SELECT sample_id FROM sample WHERE project_id = 1)
GROUP BY q.sequence_name, h.accession_txt, h.subject_desc
ORDER BY best_bit_score DESC
LIMIT 20;
```

## Quality Control

### Run QC Checks

```sql
-- Check for runs with no hits
INSERT INTO qc_check (entity_type, entity_id, check_name, status, detail)
SELECT 
  'BLAST_RUN',
  br.blast_run_id,
  'has_hits',
  CASE WHEN COUNT(h.hit_id) = 0 THEN 'FAIL' ELSE 'PASS' END,
  CONCAT('Found ', COUNT(h.hit_id), ' hits')
FROM blast_run br
LEFT JOIN hit h ON h.blast_run_id = br.blast_run_id
WHERE br.status = 'SUCCEEDED'
GROUP BY br.blast_run_id;

-- Check for suspiciously low identity matches
INSERT INTO qc_check (entity_type, entity_id, check_name, status, detail)
SELECT 
  'HIT',
  h.hit_id,
  'min_identity_threshold',
  CASE 
    WHEN h.pct_identity < 30.0 THEN 'WARN'
    WHEN h.pct_identity < 20.0 THEN 'FAIL'
    ELSE 'PASS'
  END,
  CONCAT('Identity: ', h.pct_identity, '%')
FROM hit h
WHERE h.blast_run_id IN (SELECT blast_run_id FROM blast_run WHERE status = 'SUCCEEDED');
```

### Review QC Failures

```sql
-- View all QC failures
SELECT * FROM v_qc_failures;

-- QC summary by check type
SELECT 
  check_name,
  COUNT(*) AS total_checks,
  SUM(status = 'PASS') AS passed,
  SUM(status = 'WARN') AS warnings,
  SUM(status = 'FAIL') AS failed
FROM qc_check
WHERE entity_type = 'BLAST_RUN'
GROUP BY check_name;
```

## Reporting & Analytics

### Project Performance Report

```sql
-- Comprehensive project report
SELECT 
  p.code,
  p.title,
  COUNT(DISTINCT s.sample_id) AS samples,
  COUNT(DISTINCT q.sequence_id) AS sequences,
  COUNT(DISTINCT br.blast_run_id) AS total_runs,
  SUM(br.status = 'SUCCEEDED') AS successful_runs,
  SUM(br.status = 'FAILED') AS failed_runs,
  ROUND(AVG(br.runtime_sec), 2) AS avg_runtime_sec,
  COUNT(DISTINCT sh.selected_hit_id) AS selected_hits
FROM project p
LEFT JOIN sample s ON s.project_id = p.project_id
LEFT JOIN sequence q ON q.sample_id = s.sample_id
LEFT JOIN blast_run br ON br.sequence_id = q.sequence_id
LEFT JOIN ranked_hit rh ON rh.blast_run_id = br.blast_run_id
LEFT JOIN selected_hit sh ON sh.ranked_hit_id = rh.ranked_hit_id
WHERE p.code = 'MARINE2025'
GROUP BY p.project_id, p.code, p.title;
```

### Organism Distribution Analysis

```sql
-- Top 10 organisms by hit count
SELECT 
  o.scientific_name,
  o.common_name,
  COUNT(DISTINCT h.hit_id) AS hit_count,
  AVG(h.bit_score) AS avg_bit_score,
  AVG(h.pct_identity) AS avg_identity
FROM organism o
JOIN accession a ON a.organism_id = o.organism_id
JOIN hit h ON h.accession_id = a.accession_id
JOIN blast_run br ON br.blast_run_id = h.blast_run_id
WHERE br.status = 'SUCCEEDED'
GROUP BY o.organism_id, o.scientific_name, o.common_name
ORDER BY hit_count DESC
LIMIT 10;
```

### Temporal Trend Analysis

```sql
-- Runs per day over time
SELECT 
  DATE(created_at) AS run_date,
  COUNT(*) AS runs_queued,
  SUM(status = 'SUCCEEDED') AS runs_succeeded,
  SUM(status = 'FAILED') AS runs_failed,
  ROUND(AVG(runtime_sec), 2) AS avg_runtime_sec
FROM blast_run
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY DATE(created_at)
ORDER BY run_date DESC;
```

### Performance Metrics

```sql
-- Runtime distribution
SELECT 
  CASE 
    WHEN runtime_sec < 60 THEN '< 1 min'
    WHEN runtime_sec < 300 THEN '1-5 min'
    WHEN runtime_sec < 600 THEN '5-10 min'
    WHEN runtime_sec < 1800 THEN '10-30 min'
    WHEN runtime_sec < 3600 THEN '30-60 min'
    ELSE '> 1 hour'
  END AS runtime_bucket,
  COUNT(*) AS run_count,
  ROUND(AVG(runtime_sec), 2) AS avg_seconds
FROM blast_run
WHERE status = 'SUCCEEDED'
  AND runtime_sec IS NOT NULL
GROUP BY runtime_bucket
ORDER BY avg_seconds;
```

## Data Export

### Export Results to CSV Format

```sql
-- Export top hits for a project (save results to file)
SELECT 
  p.code AS project_code,
  s.sample_code,
  q.sequence_name,
  rh.rank_position,
  h.accession_txt AS accession,
  o.scientific_name AS organism,
  h.bit_score,
  h.e_value,
  h.pct_identity,
  h.query_cover,
  h.aln_length,
  br.started_at AS run_date
FROM project p
JOIN sample s ON s.project_id = p.project_id
JOIN sequence q ON q.sample_id = s.sample_id
JOIN blast_run br ON br.sequence_id = q.sequence_id
JOIN ranked_hit rh ON rh.blast_run_id = br.blast_run_id
JOIN hit h ON h.hit_id = rh.hit_id
LEFT JOIN accession a ON a.accession_id = h.accession_id
LEFT JOIN organism o ON o.organism_id = a.organism_id
WHERE p.code = 'MARINE2025'
  AND br.status = 'SUCCEEDED'
ORDER BY q.sequence_name, rh.rank_position;
```

### Generate Summary Statistics JSON

```sql
-- Project summary as JSON
SELECT JSON_OBJECT(
  'project_code', p.code,
  'project_title', p.title,
  'statistics', JSON_OBJECT(
    'samples', COUNT(DISTINCT s.sample_id),
    'sequences', COUNT(DISTINCT q.sequence_id),
    'runs', COUNT(DISTINCT br.blast_run_id),
    'success_rate', ROUND(100.0 * SUM(br.status = 'SUCCEEDED') / COUNT(*), 2)
  ),
  'top_organisms', (
    SELECT JSON_ARRAYAGG(
      JSON_OBJECT(
        'organism', o.scientific_name,
        'hit_count', COUNT(*)
      )
    )
    FROM hit h
    JOIN blast_run br2 ON br2.blast_run_id = h.blast_run_id
    LEFT JOIN accession a ON a.accession_id = h.accession_id
    LEFT JOIN organism o ON o.organism_id = a.organism_id
    WHERE br2.sequence_id IN (
      SELECT q2.sequence_id 
      FROM sequence q2 
      JOIN sample s2 ON s2.sample_id = q2.sample_id 
      WHERE s2.project_id = p.project_id
    )
    GROUP BY o.scientific_name
    ORDER BY COUNT(*) DESC
    LIMIT 5
  )
) AS project_summary
FROM project p
LEFT JOIN sample s ON s.project_id = p.project_id
LEFT JOIN sequence q ON q.sample_id = s.sample_id
LEFT JOIN blast_run br ON br.sequence_id = q.sequence_id
WHERE p.code = 'MARINE2025'
GROUP BY p.project_id, p.code, p.title;
```

### Bulk Export for External Analysis

```sql
-- Create denormalized export table
CREATE TABLE export_blast_results AS
SELECT 
  p.code AS project,
  p.title AS project_title,
  s.sample_code,
  s.organism_note,
  s.collected_on,
  q.sequence_name,
  q.seq_length,
  br.blast_run_id,
  br.started_at,
  br.finished_at,
  br.runtime_sec,
  ps.name AS parameter_set,
  ps.program,
  tv.tool_name,
  tv.version_str,
  h.accession_txt,
  h.subject_desc,
  h.bit_score,
  h.e_value,
  h.pct_identity,
  h.query_cover,
  h.aln_length,
  o.scientific_name AS organism,
  o.ncbi_taxid
FROM project p
JOIN sample s ON s.project_id = p.project_id
JOIN sequence q ON q.sample_id = s.sample_id
JOIN blast_run br ON br.sequence_id = q.sequence_id
JOIN parameter_set ps ON ps.parameter_set_id = br.parameter_set_id
JOIN tool_version tv ON tv.tool_version_id = br.tool_version_id
JOIN hit h ON h.blast_run_id = br.blast_run_id
LEFT JOIN accession a ON a.accession_id = h.accession_id
LEFT JOIN organism o ON o.organism_id = a.organism_id
WHERE br.status = 'SUCCEEDED';

-- Export to CSV
SELECT * FROM export_blast_results
INTO OUTFILE '/tmp/blast_results_export.csv'
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n';
```

## Advanced Workflows

### Comparative Analysis Between Projects

```sql
-- Compare organism diversity across projects
SELECT 
  p.code,
  COUNT(DISTINCT o.organism_id) AS unique_organisms,
  COUNT(DISTINCT h.hit_id) AS total_hits,
  AVG(h.bit_score) AS avg_score
FROM project p
JOIN sample s ON s.project_id = p.project_id
JOIN sequence q ON q.sample_id = s.sample_id
JOIN blast_run br ON br.sequence_id = q.sequence_id
JOIN hit h ON h.blast_run_id = br.blast_run_id
LEFT JOIN accession a ON a.accession_id = h.accession_id
LEFT JOIN organism o ON o.organism_id = a.organism_id
WHERE br.status = 'SUCCEEDED'
GROUP BY p.project_id, p.code
ORDER BY unique_organisms DESC;
```

### Identify Sequences Needing Reanalysis

```sql
-- Find sequences that failed or haven't been run recently
SELECT 
  s.sample_code,
  q.sequence_name,
  MAX(br.finished_at) AS last_run,
  SUM(br.status = 'FAILED') AS failure_count
FROM sequence q
JOIN sample s ON s.sample_id = q.sample_id
LEFT JOIN blast_run br ON br.sequence_id = q.sequence_id
GROUP BY q.sequence_id, s.sample_code, q.sequence_name
HAVING 
  last_run IS NULL 
  OR last_run < DATE_SUB(NOW(), INTERVAL 6 MONTH)
  OR failure_count > 0
ORDER BY last_run ASC NULLS FIRST;
```

---

*For more examples and integration patterns, see the main [README.md](README.md) and [SCHEMA.md](SCHEMA.md) documentation.*
