# Bioinformatics BLAST Pipeline Metadata System

A MySQL database schema designed to support end-to-end BLAST/tBLASTn bioinformatics pipelines with comprehensive metadata tracking, reproducibility controls, and audit capabilities.

## Overview

This system provides a normalized relational database schema that manages the complete lifecycle of BLAST analysis workflows, from sample ingestion through hit selection and GenBank retrieval. Built for research environments requiring data integrity, reproducibility, and regulatory compliance.

## Key Features

### Data Organization & Pipeline Management
- **Hierarchical Project Structure**: Organized tracking from projects → samples → sequences → BLAST runs
- **Multi-Tool Support**: Version-controlled tracking of BLAST+ and other bioinformatics tools
- **Flexible Parameter Sets**: JSON-based parameter storage with automatic hash-based deduplication
- **File Asset Management**: SHA-256 checksums for all files (FASTA, GenBank, logs, reports)

### Reproducibility & Data Integrity
- **Input Verification**: SHA-256 checksums on canonicalized input sequences
- **Parameter Hashing**: Computed hashes ensure identical parameter sets are recognized
- **Audit Logging**: Complete tracking of user actions and entity modifications
- **QC Framework**: Extensible quality control checks with PASS/WARN/FAIL statuses

### Performance & Reporting
- **Optimized Indexing**: Strategic indexes on frequently queried columns
- **Materialized Views**: Pre-computed views for common reporting needs
- **Generated Columns**: Virtual and stored computed fields for runtime calculations
- **Hit Ranking System**: Automatic ranking of top hits per BLAST run

### Regulatory & Research Standards
- **Access Control**: Role-based user management (admin, analyst, operator)
- **Complete Audit Trail**: Time-stamped logs of all significant actions
- **Annotation Support**: Tagging and note system for collaborative workflows
- **Organism Tracking**: NCBI taxonomy integration for standardized organism identification

## Database Schema

### Core Entities

#### Project & Sample Management
- `project` - Research projects with ownership tracking
- `sample` - Biological samples with collection metadata
- `sequence` - Individual sequences from FASTA files
- `file_asset` - File storage with integrity checksums

#### BLAST Pipeline
- `tool_version` - Version tracking for bioinformatics tools
- `parameter_set` - Reusable BLAST parameter configurations
- `blast_run` - Individual pipeline executions with status tracking
- `hit` - BLAST result hits with alignment statistics
- `ranked_hit` - Top 1-3 hits per run for reporting

#### Reference Data
- `organism` - Species information with NCBI taxonomy IDs
- `accession` - GenBank/RefSeq accession tracking
- `genbank_record` - Downloaded GenBank records with feature counts

#### Governance & QC
- `app_user` & `role` - User access management
- `qc_check` - Quality control validation results
- `audit_log` - Complete action history
- `tag` & `note` - Collaborative annotation tools

### Reporting Views

The schema includes five optimized views for common reporting needs:

1. **v_latest_run_per_sequence** - Most recent successful run per sequence
2. **v_top_hits** - Top-ranked hits with organism context
3. **v_project_summary** - Project-level statistics and counts
4. **v_organism_coverage** - Distribution of selected hits by species
5. **v_qc_failures** - All failed quality control checks

## Installation

### Prerequisites
- MySQL 8.0 or higher
- Sufficient privileges to create databases and tables

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/bio-blast-pipeline.git
cd bio-blast-pipeline

# Import the schema
mysql -u your_username -p < bio_blast_meta_schema.sql
```

The script is idempotent and safe to run multiple times. It includes:
- Automatic database creation
- Foreign key consistency checks
- Default role seeding
- UTF-8 MB4 character set configuration

## Usage Examples

### Creating a New Project

```sql
-- Create a project
INSERT INTO project (code, title, description, owner_user_id)
VALUES ('PROJ001', 'Marine Microbiome Study', 'Analysis of coastal samples', 1);

-- Add samples
INSERT INTO sample (project_id, sample_code, organism_note, collected_on)
VALUES (1, 'SAMPLE_A1', 'Seawater microbiome', '2025-01-15');
```

### Launching a BLAST Run

```sql
-- Register tool version
INSERT INTO tool_version (tool_name, version_str)
VALUES ('ncbi-blast+', '2.14.1');

-- Create parameter set
INSERT INTO parameter_set (name, program, db_name, params_json)
VALUES (
  'Standard tBLASTn',
  'tblastn',
  'nr',
  '{"evalue": 1e-5, "max_target_seqs": 100, "word_size": 3}'
);

-- Launch run
INSERT INTO blast_run (sequence_id, parameter_set_id, tool_version_id, status, input_sha256, created_by)
VALUES (1, 1, 1, 'QUEUED', 'abc123...', 1);
```

### Querying Results

```sql
-- Get top hits for a specific run
SELECT * FROM v_top_hits WHERE blast_run_id = 42;

-- Project summary with success rates
SELECT * FROM v_project_summary;

-- Find all runs with failed QC
SELECT * FROM v_qc_failures WHERE entity_type = 'BLAST_RUN';
```

## Design Highlights

### Computed Columns
- **runtime_sec**: Virtual column automatically calculates run duration
- **params_hash**: Stored column generates SHA-256 hash of parameter JSON for deduplication
- **rank_key**: Virtual column for efficient hit sorting by bit score

### Data Integrity
- Foreign key constraints maintain referential integrity
- Unique constraints prevent duplicate entries
- Check constraints validate rank positions (1-3)
- Generated columns ensure consistent derived values

### Performance Optimizations
- Composite indexes on frequently joined columns
- Covering indexes for common query patterns
- Partitioning-ready design for large-scale deployments
- JSON indexing on parameter sets (MySQL 8.0+)

## Architecture Benefits

### For Research Teams
- **Reproducibility**: Every analysis can be exactly reproduced from stored parameters and checksums
- **Collaboration**: Shared projects with role-based access and annotation tools
- **Traceability**: Complete audit trail for regulatory compliance

### For Operations
- **Scalability**: Normalized design supports millions of sequences and runs
- **Monitoring**: Status tracking and runtime metrics for pipeline performance
- **Flexibility**: JSON parameter storage adapts to evolving BLAST versions

### For Data Science
- **Clean Analytics**: Optimized views provide ready-to-use reporting datasets
- **Trend Analysis**: Time-series data on run performance and organism distribution
- **Quality Metrics**: Built-in QC framework for data quality assessment

## Future Enhancements

Potential extensions to consider:
- Partitioning strategies for `blast_run` and `hit` tables by date
- Full-text indexing on `subject_desc` for semantic search
- Integration with object storage (S3/MinIO) for file assets
- GraphQL or REST API layer for programmatic access
- Real-time pipeline status dashboard

## Contributing

Contributions are welcome! Please consider:
- Adding additional QC check implementations
- Performance optimization for specific query patterns
- Integration modules for other bioinformatics tools
- Extended metadata fields for specialized workflows

## License

MIT License

## Author

**Irfan Khan - Data Science B.S. at UNC Charlotte**  
[LinkedIn](https://www.linkedin.com/in/irfan-khan-4a946a255/) | [Email](mailto:irfan.r.khan2005@gmail.com)

## Acknowledgments

Built with MySQL 8.0+ leveraging modern features including:
- JSON data type and functions
- Generated columns (virtual and stored)
- Common Table Expressions (CTEs) in views
- Advanced indexing strategies

---

*This schema represents best practices in bioinformatics data management, emphasizing reproducibility, data integrity, and operational efficiency for research and production environments.*
