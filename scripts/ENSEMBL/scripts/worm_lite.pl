#/usr/bin/env perl
#===============================================================================
#
#         FILE:  worm_lite.pl
#
#        USAGE:  ./worm_lite.pl
#
#===============================================================================

#####################################################################
# needs some makefile love to pull together all GFFs and Fastas
####################################################################

use strict;
use POSIX;
use YAML;
use Getopt::Long;
use Storable;

use Bio::Seq;
use Bio::SeqIO;
use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::Exception qw(verbose warning);
verbose('OFF');
use FindBin;
use lib "$FindBin::Bin/../lib";
use WormBase;
use DBI qw(:sql_types);

my ( $debug, $species, $setup, $dna, $genes, $rules, $inputids, $pipeline_setup, $test, $yfile );

GetOptions(
  'species=s'     => \$species,
  'setup'         => \$setup,
  'load_dna'      => \$dna,
  'load_genes'    => \$genes,
  'load_pipeline' => \$pipeline_setup,
  'load_rules'    => \$rules,
  'load_iids'     => \$inputids,
  'debug'         => \$debug,
  'test'          => \$test,
  'yfile=s'       => \$yfile,

) || die("bad commandline parameter\n");


die "You must supply a valid YAML config file\n" if not defined $yfile or not -e $yfile;

my $global_config = YAML::LoadFile($yfile);
my $generic_config = $global_config->{generics};
my $config = $global_config->{$species};
if (not $config) {
  die "Could not find config entry for species $species\n";
}

if ($test) {
  $config = $global_config->{"${species}_test"};
}
my $cvsDIR = $test
  ? $global_config->{test}->{cvsdir}
  : $generic_config->{cvsdir};


my ($prod_db_host, $prod_db_port, $prod_db_name) = 
    ($generic_config->{ensprod_host},
     $generic_config->{ensprod_port},
     $generic_config->{ensprod_dbname});

my ($tax_db_host, $tax_db_port, $tax_db_name) = 
    ($generic_config->{taxonomy_host},
     $generic_config->{taxonomy_port},
     $generic_config->{taxonomy_dbname});


$WormBase::Species = $species;

&setupdb()            if $setup;
&load_assembly()      if $dna;
&load_genes()         if $genes;
&load_rules()         if $rules or $pipeline_setup;
&load_and_input_ids() if $inputids or $pipeline_setup;

exit(0);


#########################################
sub setupdb {
  
  my $db = $config->{database};

  print ">>creating new database $db->{dbname} on $db->{host}\n";

  my $mysql = "mysql -h $db->{host} -P $db->{port} -u $db->{user} --password=$db->{password}";
  
  eval {
    print "Recreating database from scratch...\n";
    system("$mysql -e \"DROP DATABASE IF EXISTS $db->{dbname};\"") && die;
    system("$mysql -e \"create database $db->{dbname};\"")         && die;

    print "loading table.sql from ensembl...\n";
    system("$mysql $db->{dbname} < " . $cvsDIR . "/ensembl/sql/table.sql" ) && die;

    print "loading table.sql from ensembl-pipeline...\n";
    system("$mysql $db->{dbname} < " . $cvsDIR . "/ensembl-pipeline/sql/table.sql" ) && die;
    
    print "Populating meta table...\n";
    foreach my $key (keys %$config) {
      if ($key =~ /^meta\.(\S+)/) {
        my $db_key = $1;
        my $val = $config->{$key};
        
        system("$mysql -e 'INSERT INTO meta (meta_key,meta_value) VALUES (\"$db_key\",\"$val\");' $db->{dbname}") && die;
      }
    }

    print "Loading taxonomy...N";
    my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_taxonomy.pl -name \"$config->{species}\" "
        . "-taxondbhost $tax_db_host " 
        . "-taxondbport $tax_db_port "
        . "-taxondbname $tax_db_name "
        . "-lcdbhost $db->{host} "
        . "-lcdbport $db->{port} "
        . "-lcdbname $db->{dbname} "
        . "-lcdbuser $db->{user} "
        . "-lcdbpass $db->{password}";
    print "$cmd\n";        
    system($cmd) and die "Could not load taxonomy\n";
    
    print "Loading production table...\n";
    $cmd = "perl $cvsDIR/ensembl/misc-scripts/production_database/scripts/populate_production_db_tables.pl "
        . "--host $db->{host} "
        . "--user $db->{user} "
        . "--pass $db->{password} "
        . "--port $db->{port} "
        . "--database $db->{dbname} "
        . "--mhost $prod_db_host "
        . "--mport $prod_db_port "
        . "--mdatabase $prod_db_name "
	. "--dropbaks "
	. "--dumppath /tmp/ ";
    print "$cmd\n";
    system($cmd) and die "Could not populate production tables\n";

    my $db_opt_string = sprintf("-dbhost %s -dbport %s -dbuser %s -dbpass %s -dbname %s", 
                                $db->{host},
                                $db->{port},
                                $db->{user},
                                $db->{password},
                                $db->{dbname});

    my @ana_conf_files;

    if ($generic_config->{analysisconf}) {
      push @ana_conf_files, $generic_config->{analysisconf};
    }
    if ($config->{analysisconf}) {
      push @ana_conf_files, $config->{analysisconf};
    }
    
    foreach my $cfile (@ana_conf_files) {
      if (-e $cfile) {
        print "Loading analyses...\n";
        $cmd = "perl $FindBin::Bin/analysis_setup.pl $db_opt_string -read -file $cfile";
        print "Running: $cmd\n";
        system($cmd) and die "Could not load analyses from $cfile\n";
      } else {
        die "Could not find analysis config file $cfile\n";
      }
    }


  };
  $@ and die("Error while building the database: $@");
}

##############################################
sub load_assembly {
  
  my $db = $config->{database};
  
  my $seq_level_coord_sys = $config->{seqlevel};
  my $top_level_coord_sys = $config->{toplevel};
  my $coord_sys_ver = $config->{assembly_version};

  my $seq_level_rank = ($seq_level_coord_sys eq $top_level_coord_sys) ? 1 : 2;
  my $top_level_rank = 1;

  if ($config->{agp}) {
    foreach my $glb (split(/,/, $config->{agp})) {
      foreach my $agp (glob("$glb")) {
        my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_seq_region.pl "
            . "-dbhost $db->{host} "
            . "-dbuser $db->{user} "
            . "-dbpass $db->{password} "
            . "-dbname $db->{dbname} "
            . "-dbport $db->{port} "
            . "-coord_system_name $top_level_coord_sys "
            . "-coord_system_version $coord_sys_ver "
            . "-rank $top_level_rank "
            . "-default_version "
            . "-agp_file $agp";
        print "Running: $cmd\n";
        system($cmd) and die "Could not load seq_regions from agp file\n";
      }
    }
  }

  foreach my $glb (split(/,/, $config->{fasta})) {
    foreach my $fasta (glob("$glb")) {
      my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_seq_region.pl "
          . "-dbhost $db->{host} "
          . "-dbuser $db->{user} "
          . "-dbpass $db->{password} "
          . "-dbname $db->{dbname} "
          . "-dbport $db->{port} "
          . "-coord_system_name $seq_level_coord_sys "
          . "-coord_system_version $coord_sys_ver "
          . "-rank $seq_level_rank "
          . "-default_version -sequence_level "
          . "-fasta_file $fasta";
      print "Running: $cmd\n";
      system($cmd) and die "Could not load seq_regions fasta file\n";
    }
  }

  if ($config->{agp}) {
    foreach my $glb (split(/,/, $config->{agp})) {
      foreach my $agp (glob("$glb")) {
        my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_agp.pl "
            . "-dbhost $db->{host} "
            . "-dbuser $db->{user} "
            . "-dbpass $db->{password} "
            . "-dbname $db->{dbname} "
            . "-dbport $db->{port} "
            . "-assembled_name $top_level_coord_sys "
            . "-assembled_version $coord_sys_ver "
            . "-component_name $seq_level_coord_sys "
            . "-component_version $coord_sys_ver "
            . "-agp_file $agp";
        print "Running: $cmd\n";
        system($cmd) and die "Could not load the assembly table from agp file\n";
      }
    }
  }
  
  my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/set_toplevel.pl "
      . "-dbhost $db->{host} "
      . "-dbport $db->{port} "
      . "-dbuser $db->{user} "
      . "-dbpass $db->{password} "
      . "-dbname $db->{dbname}" ;
  print "Running: $cmd\n";
  system($cmd) and die "Could not set toplevel\n";
  
  if ($config->{mitochondrial}) {
    my @mito_seqs = split(/,/, $config->{mitochondrial});

    $cmd = "perl $FindBin::Bin/set_codon_table.pl "
        . "-dbhost $db->{host} "
        . "-dbport $db->{port} "
        . "-dbuser $db->{user} "
        . "-dbpass $db->{password} "
        . "-dbname $db->{dbname} "
        . "-codontable 5 "
        . "@mito_seqs";
    print "Running: $cmd\n";
    system($cmd) and die "Could not set the mitochrondrial table";
  }

  # Finally, for elegans and briggsae, append the chromosome prefices (yuk, but it has to 
  # done to make BLAST dumping etc work properly
  if ($species eq 'elegans' or $species eq 'briggsae') {
    my $prefix = ($species eq 'elegans') ? 'CHROMOSOME_' : 'chr';

    my $mysql = "mysql -h $db->{host} -P $db->{port} -u $db->{user} --password=$db->{password} -D $db->{dbname}";
    my $sql = "UPDATE seq_region, coord_system "
        . "SET seq_region.name = CONCAT(\"$prefix\", seq_region.name) "
        . "WHERE seq_region.coord_system_id = coord_system.coord_system_id "
        . "AND coord_system.name = \"chromosome\"";
    print "Running: $mysql -e '$sql'\n";
    system("$mysql -e '$sql'") and die "Could not add chromosome prefixes to chromosome names\n";
  }

}

#############################################
sub load_genes {

  my $db = $config->{database};

  my $dba = new Bio::EnsEMBL::DBSQL::DBAdaptor(
    -host   => $db->{host},
    -user   => $db->{user},
    -dbname => $db->{dbname},
    -pass   => $db->{password},
    -port   => $db->{port},
      );

  my (%ana_hash, $analysis);

  foreach my $ana (@{$dba->get_AnalysisAdaptor->fetch_all}) {
    $ana_hash{$ana->logic_name} = $ana;
  }
  if (not exists $ana_hash{wormbase}) {
    my $ana = Bio::EnsEMBL::Analysis->new(-logic_name => "wormbase", 
                                          -gff_source => "WormBase",
                                          -module => "WormBase");
    $dba->get_AnalysisAdaptor->store($ana);
    $ana_hash{wormbase} = $ana;
  }
  $analysis = $ana_hash{wormbase};

  my (%slice_hash, @path_globs, @gff2_files, @gff3_files, $genes); 

  foreach my $slice (@{$dba->get_SliceAdaptor->fetch_all('toplevel')}) {
    $slice_hash{$slice->seq_region_name} = $slice;
    if ($species eq 'elegans') {
      my $other_name;
      if ($slice->seq_region_name !~ /^CHROMOSOME/) {
        $other_name = "CHROMOSOME_" . $slice->seq_region_name; 
      } else {
        $other_name = $slice->seq_region_name;
        $other_name =~ s/^CHROMOSOME_//;
      }
      $slice_hash{$other_name} = $slice;
    } elsif ($species eq 'briggsae') {
      my $other_name;
      if ($slice->seq_region_name !~ /^chr/) {
        $other_name = "chr" . $slice->seq_region_name; 
      } else {
        $other_name = $slice->seq_region_name;
        $other_name =~ s/^chr//;
      }
      $slice_hash{$other_name} = $slice;
    }
  }
  
  if ($config->{gff}) {
    @path_globs = split(/,/, $config->{gff});
    foreach my $fglob (@path_globs) {
      push @gff2_files, glob($fglob);
    }
  } elsif ($config->{gff3}) {
    @path_globs = split(/,/, $config->{gff3});
    foreach my $fglob (@path_globs) {
      push @gff3_files, glob($fglob);
    }
  } else {
    die "No gff or gff3 stanza in config - death\n";
  }

  if (@gff2_files) {
    open(my $gff_fh, "cat @gff2_files |") or die "Could not create GFF stream\n";
    $genes = &parse_gff_fh( $gff_fh, \%slice_hash, $analysis);
  } elsif (@gff3_files) {
    open(my $gff_fh, "cat @gff3_files |") or die "Could not create GFF stream\n";
    $genes = &parse_gff3_fh( $gff_fh, \%slice_hash, \%ana_hash);
  } else {
    die "No gff or gff3 files found - death\n";
  }

  &write_genes( $genes, $dba );
  
  my $set_canon_cmd = "perl $cvsDIR/ensembl/misc-scripts/canonical_transcripts/set_canonical_transcripts.pl "
      . "-dbhost $db->{host} "
      . "-dbuser $db->{user} "
      . "-dbpass $db->{password} "
      . "-dbname $db->{dbname} "
      . "-dbport $db->{port} "
      . "-coord toplevel "
      . "-write";
  print "Running: $set_canon_cmd\n";
  system($set_canon_cmd) and die "Could not set canonical transcripts\n";

  my $timestamp = strftime("%Y-%m", localtime(time));
  
  $dba->dbc->do('DELETE FROM  meta WHERE meta_key = "genebuild.start_date"');
  $dba->dbc->do("INSERT INTO meta (meta_key,meta_value) VALUES (\"genebuild.start_date\",\"$timestamp\")");
}


#############################################
sub load_rules {
  my $db = $config->{database};

  my @conf_files;
  foreach my $path ($generic_config->{ruleconf}, $config->{ruleconf}) {
    if ($path) {
      foreach my $file (split(/,/, $path)) {
        if (-e $file) {
          push @conf_files, $file;
        } else {
          die "Rule config file $file could not be found\n";
        } 
      }
    }
  }
    
  my $load_rule_base = "perl $cvsDIR/ensembl-pipeline/scripts/rule_setup.pl "
      . "-dbhost $db->{host} "
      . "-dbuser $db->{user} "
      . "-dbpass $db->{password} "
      . "-dbname $db->{dbname} "
      . "-dbport $db->{port} "
      . "-read "
      . "-file ";
    
  foreach my $cfile (@conf_files) {
    if (-e $cfile) {
      print "Loading rules from $cfile...\n";
      my $cmd = "$load_rule_base $cfile";
      print "Running: $cmd\n";
      system($cmd) and die "Could not load analyses from $cfile\n";
    } else {
      die "Could not find analysis config file $cfile\n";
    }
  }
}



#############################################
sub load_input_ids {
  my $db = $config->{database};

  my $load_input_ids_base =  "perl $cvsDIR/ensembl-pipeline/scripts/make_input_ids "
      . "-dbhost $db->{host} "
      . "-dbuser $db->{user} "
      . "-dbpass $db->{password} "
      . "-dbname $db->{dbname} "
      . "-dbport $db->{port} ";

  my $slice_cmd = "$load_input_ids_base -slice -slice_size 75000 -coord_system toplevel -logic_name submitslice75k -input_id_type SLICE75K";
  my $trids_cmd = "$load_input_ids_base -translation_id -logic submittranslation";

  foreach my $cmd ($slice_cmd, $trids_cmd) {
    print "Running: $cmd\n";
    system($cmd) and die "Could not successfully make input ids\n";
  }

}
