#!/usr/bin/env perl
use ProductionMysql;
use feature 'say';
my $species = shift or die "Usage: $0: species"; 

my $source = ProductionMysql->previous_staging->conn;
say "sourcehost=",$source->{host};
say "sourceport=",$source->{port};
say "sourceuser=",$source->{user};
say "sourcedbname=", ProductionMysql->previous_staging->core_databases($species);

my $target=ProductionMysql->staging->conn;
say "targethost=",$target->{host};
say "targetport=",$target->{port};
say "targetuser=",$target->{user};
say "targetdbname=", ProductionMysql->staging->core_databases($species);

say "urlprefix=", "https://parasite.wormbase.org/$species/Gene/Summary?g=";

while(<DATA>){
 print;
}
__DATA__
;; for dry runs, no data is written to the database
dry_run = 1

;; log level, useful values are 'INFO' or 'DEBUG'
loglevel = DEBUG

;; paths

;; URL prefix for navigation

;; old/source database settings


;; new/target database settings

;; the production database

productionhost = mysql-eg-pan-prod.ebi.ac.uk
productionport = 4276
productionuser = ensro
productiondbname = ensembl_production_parasite

;; caching
;cache_method                = build_cache_all
build_cache_auto_threshold  = 2000
build_cache_concurrent_jobs = 25

;; include only some biotypes
;biotypes_include=protein_coding,pseudogene,retrotransposed
;; alternatively, exclude some biotypes
;biotypes_exclude=protein_coding,pseudogene,retrotransposed

;; LSF parameters
lsf_opt_run_small           = "-q production-rh7 "
lsf_opt_run                 = "-q production-rh7 -We 90 -M20000 -R 'select[mem>20000]' -R  'rusage[mem=20000]'"
lsf_opt_dump_cache          = "-q production-rh7 -We 5 -M8000 -R 'select[mem>8000]'  -R 'rusage[mem=8000]'"

transcript_score_threshold  = 0.25
gene_score_threshold        = 0.125

;; Exonerate
min_exon_length             = 15
exonerate_path              = /nfs/software/ensembl/RHEL7/linuxbrew/bin/exonerate
exonerate_bytes_per_job     = 2500000
exonerate_concurrent_jobs   = 200
exonerate_threshold         = 0.5
exonerate_extra_params      = '--bestn 100'
lsf_opt_exonerate           = "-q production-rh7 -We 10 -M16000 -R 'select[mem>16000]' -R 'rusage[mem=16000]'"

synteny_rescore_jobs        = 20
lsf_opt_synteny_rescore     = "-q production-rh7 -We 10 -M16000 -R 'select[mem>16000]' -R  'rusage[mem=16000]'"

;; StableIdMapper
mapping_types               = gene,transcript,translation,exon

plugin_stable_id_generator = IdMapping::TemporaryIdGenerator
starting_gene_stable_id = TmpG00000000001
starting_transcript_stable_id = TmpT00000000001
starting_exon_stable_id = TmpE00000000001
starting_translation_stable_id = TmpP00000000001

;; upload results into db
upload_events               = 1
upload_stable_ids           = 1
upload_archive              = 1
