# Database Schema Documentation

## Table of Contents
1. [Schema Overview](#schema-overview)
2. [Entity Relationship Diagram](#entity-relationship-diagram)
3. [Table Definitions](#table-definitions)
4. [Views](#views)
5. [Indexes](#indexes)
6. [Data Flow](#data-flow)

## Schema Overview

The `bio_blast_meta` database provides comprehensive metadata management for BLAST bioinformatics pipelines. The schema is organized into several logical domains:

### Domain Organization

| Domain | Tables | Purpose |
|--------|--------|---------|
| **Access Control** | `role`, `app_user`, `user_role` | User authentication and authorization |
| **Project Data** | `project`, `sample`, `sequence`, `file_asset` | Research data hierarchy |
| **Pipeline Tools** | `tool_version`, `parameter_set` | Tool and configuration management |
| **BLAST Execution** | `blast_run`, `hit`, `ranked_hit` | Pipeline execution and results |
| **Reference Data** | `organism`, `accession`, `genbank_record` | External biological databases |
| **Governance** | `qc_check`, `audit_log`, `tag`, `note` | Quality control and audit trail |
| **Selection** | `selected_hit` | User-curated result selection |

## Entity Relationship Diagram

```
project (1) ──→ (N) sample (1) ──→ (N) sequence
   ↓                                      ↓
app_user                          blast_run (N) ──→ (1) parameter_set
   ↓                                      ↓
user_role ──→ role                       hit (N) ──→ (1) accession ──→ organism
                                          ↓
                                    ranked_hit ──→ selected_hit ──→ genbank_record
```

## Table Definitions

### Access Control Tables

#### `role`
Defines system roles for access control.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| role_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique role identifier |
| name | VARCHAR(64) | NOT NULL, UNIQUE | Role name (e.g., 'admin', 'analyst') |
| description | VARCHAR(255) | | Role description |

**Seeded Data**: admin, analyst, operator

#### `app_user`
System users who can launch runs and own projects.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| user_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique user identifier |
| email | VARCHAR(191) | NOT NULL, UNIQUE | User email address |
| display_name | VARCHAR(128) | NOT NULL | Display name |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Account creation time |

**Indexes**: Unique on `email`

#### `user_role`
Many-to-many mapping between users and roles.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| user_id | BIGINT UNSIGNED | PK, FK → app_user | User reference |
| role_id | BIGINT UNSIGNED | PK, FK → role | Role reference |
| assigned_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Assignment timestamp |

**Composite Primary Key**: (user_id, role_id)

---

### Project Data Tables

#### `project`
Top-level research projects.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| project_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique project identifier |
| code | VARCHAR(64) | NOT NULL, UNIQUE | Short project code (e.g., 'PROJ001') |
| title | VARCHAR(191) | NOT NULL | Project title |
| description | TEXT | | Detailed description |
| owner_user_id | BIGINT UNSIGNED | FK → app_user | Project owner |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Creation timestamp |

**Indexes**: Unique on `code`

#### `sample`
Biological samples within projects.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| sample_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique sample identifier |
| project_id | BIGINT UNSIGNED | NOT NULL, FK → project | Parent project |
| sample_code | VARCHAR(64) | NOT NULL | Sample code within project |
| organism_note | VARCHAR(191) | | Free-text organism description |
| collected_on | DATE | | Sample collection date |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation time |

**Indexes**: 
- Unique on `(project_id, sample_code)`
- Foreign key on `project_id`

#### `sequence`
Individual sequences from FASTA files.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| sequence_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique sequence identifier |
| sample_id | BIGINT UNSIGNED | NOT NULL, FK → sample | Parent sample |
| fasta_file_id | BIGINT UNSIGNED | NOT NULL, FK → file_asset | Source FASTA file |
| sequence_name | VARCHAR(191) | NOT NULL | FASTA header ID |
| seq_length | INT UNSIGNED | NOT NULL | Sequence length in bp/aa |
| fasta_sha256 | CHAR(64) | NOT NULL | SHA-256 of sequence text |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation time |

**Indexes**: 
- Unique on `(sample_id, sequence_name)`
- Index on `sample_id`
- Foreign keys on `sample_id`, `fasta_file_id`

#### `file_asset`
Managed files with integrity checking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| file_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique file identifier |
| file_type | ENUM | NOT NULL | FASTA, GENBANK, LOG, REPORT, OTHER |
| uri | VARCHAR(512) | NOT NULL | File path or object store URI |
| sha256_hex | CHAR(64) | NOT NULL, UNIQUE | SHA-256 checksum |
| byte_size | BIGINT UNSIGNED | | File size in bytes |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation time |

**Indexes**: 
- Unique on `sha256_hex`
- Index on `file_type`

---

### Pipeline Tools Tables

#### `tool_version`
Tracks versions of bioinformatics tools.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| tool_version_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique version identifier |
| tool_name | VARCHAR(64) | NOT NULL | Tool name (e.g., 'blast+') |
| version_str | VARCHAR(64) | NOT NULL | Version string (e.g., '2.14.1') |
| build_meta | VARCHAR(191) | | Additional build information |

**Indexes**: Unique on `(tool_name, version_str)`

#### `parameter_set`
Reusable BLAST parameter configurations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| parameter_set_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique parameter set ID |
| name | VARCHAR(128) | NOT NULL, UNIQUE | Human-friendly name |
| program | ENUM | NOT NULL | blastn, blastp, tblastn, tblastx, blastx |
| db_name | VARCHAR(191) | NOT NULL | Target database name |
| params_json | JSON | NOT NULL | Full parameter map |
| params_hash | CHAR(64) | GENERATED, STORED | SHA-256 of pretty-printed JSON |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Creation time |

**Generated Column**: `params_hash = UPPER(SHA2(JSON_PRETTY(params_json), 256))`

**Indexes**: 
- Unique on `name`
- Unique on `(program, db_name, params_hash)` - prevents parameter duplication

---

### BLAST Execution Tables

#### `blast_run`
Individual BLAST pipeline executions.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| blast_run_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique run identifier |
| sequence_id | BIGINT UNSIGNED | NOT NULL, FK → sequence | Input sequence |
| parameter_set_id | BIGINT UNSIGNED | NOT NULL, FK → parameter_set | Parameters used |
| tool_version_id | BIGINT UNSIGNED | NOT NULL, FK → tool_version | Tool version used |
| status | ENUM | NOT NULL, DEFAULT 'QUEUED' | QUEUED, RUNNING, SUCCEEDED, FAILED |
| node_host | VARCHAR(128) | | Compute node hostname |
| started_at | DATETIME | | Run start time |
| finished_at | DATETIME | | Run completion time |
| runtime_sec | INT UNSIGNED | GENERATED, VIRTUAL | Computed: finished_at - started_at |
| input_sha256 | CHAR(64) | NOT NULL | Checksum of canonicalized input |
| created_by | BIGINT UNSIGNED | FK → app_user | User who launched run |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation time |

**Generated Column**: `runtime_sec = TIMESTAMPDIFF(SECOND, started_at, finished_at)`

**Indexes**: 
- Index on `(sequence_id, created_at)`
- Index on `status`
- Foreign keys on `sequence_id`, `parameter_set_id`, `tool_version_id`, `created_by`

#### `hit`
BLAST search results.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| hit_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique hit identifier |
| blast_run_id | BIGINT UNSIGNED | NOT NULL, FK → blast_run | Parent BLAST run |
| accession_id | BIGINT UNSIGNED | FK → accession | Normalized accession (optional) |
| accession_txt | VARCHAR(64) | NOT NULL | Raw accession as reported |
| subject_desc | VARCHAR(512) | | Subject sequence description |
| bit_score | DOUBLE | NOT NULL | BLAST bit score |
| e_value | DOUBLE | NOT NULL | Expect value |
| pct_identity | DECIMAL(6,3) | NOT NULL | Percent identity (0-100) |
| query_cover | DECIMAL(6,3) | NOT NULL | Query coverage (0-100) |
| aln_length | INT UNSIGNED | | Alignment length |
| hsp_summary | TEXT | | JSON/text summary of HSPs |
| rank_key | VARCHAR(64) | GENERATED, VIRTUAL | Sortable key based on -bit_score |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation time |

**Generated Column**: `rank_key = LPAD(CAST(ROUND(-bit_score * 1000) AS SIGNED), 8, '0')`

**Indexes**: 
- Index on `blast_run_id`
- Foreign keys on `blast_run_id`, `accession_id`

#### `ranked_hit`
Top 1-3 hits per BLAST run for reporting.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| ranked_hit_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique ranked hit ID |
| blast_run_id | BIGINT UNSIGNED | NOT NULL, FK → blast_run | Parent run |
| hit_id | BIGINT UNSIGNED | NOT NULL, FK → hit | Ranked hit |
| rank_position | TINYINT UNSIGNED | NOT NULL, CHECK(1-3) | Position (1, 2, or 3) |

**Indexes**: 
- Unique on `(blast_run_id, rank_position)`
- Index on `hit_id`
- Check constraint ensures `rank_position IN (1, 2, 3)`

---

### Reference Data Tables

#### `organism`
Organism taxonomy information.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| organism_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique organism ID |
| scientific_name | VARCHAR(191) | NOT NULL | Scientific name |
| common_name | VARCHAR(191) | | Common name |
| ncbi_taxid | INT UNSIGNED | | NCBI Taxonomy ID |

**Indexes**: Unique on `(scientific_name, COALESCE(ncbi_taxid, 0))`

#### `accession`
GenBank/RefSeq accession numbers.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| accession_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique accession ID |
| accession | VARCHAR(64) | NOT NULL | Accession number |
| version | VARCHAR(16) | | Version number |
| molecule | ENUM | NOT NULL, DEFAULT 'nucl' | nucl, prot, other |
| organism_id | BIGINT UNSIGNED | FK → organism | Associated organism |

**Indexes**: 
- Unique on `(accession, COALESCE(version, ''))`
- Index on `organism_id`

#### `genbank_record`
Downloaded GenBank records.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| genbank_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique GenBank record ID |
| accession_id | BIGINT UNSIGNED | NOT NULL, FK → accession | Associated accession |
| version | VARCHAR(16) | | Record version |
| features_count | INT UNSIGNED | | Number of features |
| locus | VARCHAR(191) | | Locus name |
| length_bp | INT UNSIGNED | | Sequence length |
| file_id | BIGINT UNSIGNED | NOT NULL, FK → file_asset | GenBank file |
| downloaded_at | DATETIME | NOT NULL | Download timestamp |

**Indexes**: 
- Unique on `(accession_id, COALESCE(version, ''))`
- Foreign keys on `accession_id`, `file_id`

---

### Governance Tables

#### `qc_check`
Quality control validation results.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| qc_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique QC check ID |
| entity_type | ENUM | NOT NULL | PROJECT, SAMPLE, SEQUENCE, BLAST_RUN, HIT, GENBANK |
| entity_id | BIGINT UNSIGNED | NOT NULL | ID of checked entity |
| check_name | VARCHAR(128) | NOT NULL | Check identifier |
| status | ENUM | NOT NULL | PASS, WARN, FAIL |
| detail | TEXT | | Detailed results |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Check timestamp |

**Indexes**: 
- Index on `(entity_type, entity_id)`
- Index on `status`

#### `audit_log`
Complete action history.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| audit_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique audit entry ID |
| user_id | BIGINT UNSIGNED | FK → app_user | User who performed action |
| action | VARCHAR(128) | NOT NULL | Action type |
| entity_type | VARCHAR(64) | NOT NULL | Affected entity type |
| entity_id | BIGINT UNSIGNED | NOT NULL | Affected entity ID |
| at_time | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Action timestamp |
| meta | JSON | | Additional metadata |

**Indexes**: 
- Index on `(entity_type, entity_id, at_time)`
- Index on `(user_id, at_time)`

#### `tag`
Reusable tags for annotation.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| tag_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique tag ID |
| name | VARCHAR(64) | NOT NULL, UNIQUE | Tag name |

#### `tag_map`
Many-to-many mapping of tags to entities.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| tag_id | BIGINT UNSIGNED | PK, FK → tag | Tag reference |
| entity_type | VARCHAR(32) | PK | Entity type |
| entity_id | BIGINT UNSIGNED | PK | Entity ID |
| tagged_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Tagging timestamp |

**Composite Primary Key**: (tag_id, entity_type, entity_id)

#### `note`
Free-text annotations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| note_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique note ID |
| entity_type | VARCHAR(32) | NOT NULL | Entity type |
| entity_id | BIGINT UNSIGNED | NOT NULL | Entity ID |
| author_id | BIGINT UNSIGNED | FK → app_user | Note author |
| body | TEXT | NOT NULL | Note content |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Creation timestamp |

**Indexes**: Index on `(entity_type, entity_id, created_at)`

---

### Selection Tables

#### `selected_hit`
User-curated selection of hits for further analysis.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| selected_hit_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT | Unique selection ID |
| ranked_hit_id | BIGINT UNSIGNED | NOT NULL, UNIQUE, FK → ranked_hit | Selected ranked hit |
| genbank_id | BIGINT UNSIGNED | FK → genbank_record | Associated GenBank record (if downloaded) |
| selected_by | BIGINT UNSIGNED | FK → app_user | User who selected |
| selected_at | DATETIME | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Selection timestamp |

**Indexes**: 
- Unique on `ranked_hit_id`
- Foreign keys on `ranked_hit_id`, `genbank_id`, `selected_by`

---

## Views

### v_latest_run_per_sequence
Returns the most recent successful BLAST run for each sequence.

```sql
SELECT br.*
FROM blast_run br
JOIN (
  SELECT sequence_id, MAX(finished_at) AS max_finished
  FROM blast_run
  WHERE status = 'SUCCEEDED'
  GROUP BY sequence_id
) t ON t.sequence_id = br.sequence_id AND t.max_finished = br.finished_at;
```

**Use Cases**: Finding current results, avoiding reprocessing

### v_top_hits
Shows top 1-3 ranked hits per run with organism context.

```sql
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
```

**Use Cases**: Quick result browsing, export for reports

### v_project_summary
Aggregated statistics per project.

```sql
SELECT
  p.project_id,
  p.code,
  p.title,
  COUNT(DISTINCT s.sample_id) AS samples,
  COUNT(DISTINCT q.sequence_id) AS sequences,
  COUNT(DISTINCT br.blast_run_id) AS runs,
  SUM(br.status='SUCCEEDED') AS runs_succeeded,
  SUM(br.status='FAILED') AS runs_failed
FROM project p
LEFT JOIN sample s ON s.project_id = p.project_id
LEFT JOIN sequence q ON q.sample_id = s.sample_id
LEFT JOIN blast_run br ON br.sequence_id = q.sequence_id
GROUP BY p.project_id, p.code, p.title;
```

**Use Cases**: Dashboard metrics, project health monitoring

### v_organism_coverage
Distribution of selected hits by organism.

```sql
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
```

**Use Cases**: Trend analysis, organism preference patterns

### v_qc_failures
All failed quality control checks.

```sql
SELECT *
FROM qc_check
WHERE status = 'FAIL'
ORDER BY created_at DESC;
```

**Use Cases**: QC monitoring, data quality dashboards

---

## Indexes

### Strategic Index Design

| Table | Index | Columns | Purpose |
|-------|-------|---------|---------|
| blast_run | idx_run_sequence | (sequence_id, created_at) | Finding runs by sequence |
| blast_run | idx_run_status | (status) | Filtering by run status |
| file_asset | idx_file_type | (file_type) | Filtering by file type |
| qc_check | idx_qc_entity | (entity_type, entity_id) | Looking up QC results |
| audit_log | idx_audit_entity | (entity_type, entity_id, at_time) | Audit trail queries |
| note | idx_note_entity | (entity_type, entity_id, created_at) | Note retrieval |

### Unique Constraints for Data Integrity

- `project.code` - Prevents duplicate project codes
- `sample.(project_id, sample_code)` - Ensures unique samples within projects
- `sequence.(sample_id, sequence_name)` - Prevents duplicate sequence names
- `file_asset.sha256_hex` - Content-based deduplication
- `parameter_set.(program, db_name, params_hash)` - Prevents duplicate parameter sets
- `ranked_hit.(blast_run_id, rank_position)` - Ensures valid ranking

---

## Data Flow

### Typical Pipeline Execution Flow

1. **Project Setup**
   ```
   project → sample → sequence (with file_asset)
   ```

2. **Run Configuration**
   ```
   tool_version + parameter_set → ready for execution
   ```

3. **BLAST Execution**
   ```
   blast_run (QUEUED) → (RUNNING) → (SUCCEEDED/FAILED)
   └→ hit records created
   └→ ranked_hit populated (top 3)
   └→ qc_check performed
   ```

4. **Result Selection**
   ```
   ranked_hit → selected_hit
   └→ trigger GenBank download
   └→ genbank_record created
   ```

5. **Audit Trail**
   ```
   All actions → audit_log entries
   User annotations → tag_map, note
   ```

### Data Integrity Checkpoints

| Stage | Validation | Table |
|-------|-----------|-------|
| File Upload | SHA-256 verification | file_asset |
| Run Input | Canonicalized sequence checksum | blast_run.input_sha256 |
| Parameter Reuse | JSON hash matching | parameter_set.params_hash |
| Result Ranking | Top 3 constraint | ranked_hit (check constraint) |
| QC Validation | Automated checks | qc_check |

---

## Performance Considerations

### Optimization Strategies

1. **Partitioning Candidates**
   - `blast_run` by `created_at` (monthly/quarterly)
   - `hit` by `blast_run_id` (hash partitioning)
   - `audit_log` by `at_time` (range partitioning)

2. **Archival Strategy**
   - Move `blast_run.status = 'FAILED'` runs older than 6 months
   - Archive `audit_log` entries older than 2 years
   - Compress GenBank files in `file_asset`

3. **Query Optimization**
   - Use views for common queries
   - Consider materialized views for heavy aggregations
   - Add covering indexes for report-heavy workloads

4. **Scaling Considerations**
   - Separate read replicas for reporting
   - Connection pooling for high-concurrency workloads
   - Consider sharding by `project_id` at extreme scale

---

*This documentation reflects schema version 1.0 as of 2025-09-28*
