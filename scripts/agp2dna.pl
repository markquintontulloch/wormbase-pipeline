#!/usr/local/bin/perl5.8.0 -w
#
# agp2dna.pl
#
# by Dan Lawson
#
# Reconstructs chromosome DNA consensus file from the agp file.
# Each clone segment of sequence is checked from the EMBL
# entry and the acedb derived DNA file.
#
# Usage : agp2dna.pl [-options]
#
# Last edited by: $Author: gw3 $
# Last edited on: $Date: 2006-05-09 12:43:08 $

use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Storable;
use Log_files;

use vars qw ($seq_len $sv_acc $sv_ver );


########################################
# command-line options                 #
########################################

my $debug;              # Verbose debug mode
my $help;               # Help/Usage page
my $chrom;              # Single chromosome mode - provide chromosome name
my $pfetch;             # Fetch sequences using pfetch
my $getz;               # Fetch sequences using getz
my $test;               # use test environment in ~wormpub/TEST_BUILD
my $quicktest;          # same as -test but only uses one chromosome
my $verbose;
my $store;
my $wormbase;

GetOptions (
            "pfetch"      => \$pfetch,
            "getz"        => \$getz,
	    "debug=s"     => \$debug,
            "help"        => \$help,
	    "chrom=s"     => \$chrom,
	    "test"        => \$test,
	    "quicktest"   => \$quicktest,
	    "verbose"     => \$verbose,
	    "store:s"     => \$store
	   );
($test = 1) if ($quicktest);


if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
			     );
}

# Display help if required
&usage("Help") if ($help);

# in test mode?
if ($test) {
  print "In test mode\n" if ($verbose);

}

# establish log file.
my $log = Log_files->make_build_log($wormbase);


##############################
# Script variables (run)     #
##############################

# Set up top level base directory which is different if in test mode
# Make all other directories relative to this
my $basedir   = $wormbase->basedir;
my $dnadir    = $wormbase->chromosomes;
my $logdir    = $wormbase->autoace."/yellow_brick_road";

my @gff_files = ('I','II','III','IV','V','X');
@gff_files = ('III') if ($quicktest);


# Set pfetch as the default retreival option
if (!$getz) {$pfetch = 1};


# single chromosome mode
if ($chrom) {
  @gff_files = ();
  &usage(5) unless (($chrom eq "I") || ($chrom eq "II") || ($chrom eq "III") || ($chrom eq "IV") || ($chrom eq "V") || ($chrom eq "X"));
  push (@gff_files, $chrom);
}

 ########################################
 # Loop over each chromosome            # 
 ########################################

foreach my $chromosome (@gff_files) {
    
  # reset sequence strings (prevents concatenation across chromosomes)
  my $wormbase_seq = "";
  my $seq_con="";
  
  open (DNA, "<$dnadir/CHROMOSOME_$chromosome.dna") || &usage(1);
  while (<DNA>) {
    chomp;
    next if (/^>/);
    $wormbase_seq .= $_;
  }
  close DNA;
  
  # variables used in agp file loop
  my ($acc,$sv,$seq_ndb,$from,$to,$span,$start,$new_seq);
  my ($EMBL_acc,$EMBL_sv,$EMBL_seq,$EMBL_slice);
  my ($wormbase_slice,$wormbase_len,$agp_len);
  
  open (AGPLOG, ">$logdir/CHROMOSOME_$chromosome.agp_seq.log") || &usage(3);
  open (AGP, "<$logdir/CHROMOSOME_$chromosome.agp") || &usage(2);
  while (<AGP>) {
    ($acc,$sv,$seq_ndb,$from,$to,$span,$start,$new_seq) = "";
    my @f = split (/\s+/);
    
    # do block if not a gap
    unless ($f[4] eq "N") {
      ($acc,$sv) = split (/\./,$f[5]);
      $from  = $f[6] ;                 # sequence coords to string slice
      $to    = $f[7] ;                 # sequence coords to string slice
      $start = $f[6] - 1;
      $span  = $f[7] - $f[6] + 1;
      
      # fetch the EMBL entry
      ($EMBL_acc,$EMBL_sv,$EMBL_seq,$EMBL_slice) = "" ;
      
      if ($pfetch) {
	($EMBL_acc,$EMBL_sv,$EMBL_seq) = &sequence_pfetch($acc);
      }
      elsif ($getz) {
	($EMBL_acc,$EMBL_sv,$EMBL_seq) = &sequence_getz($acc);
      }
      
      $EMBL_slice = substr($EMBL_seq,$start,$span);
      
      # wrong orientation handling
      if ($f[8] eq "-") {
	$EMBL_slice = substr($EMBL_seq,-$span);
	$EMBL_slice = $wormbase->DNA_string_reverse($EMBL_slice);
      }
      
      # check against WormBase sequence
      $wormbase_slice = substr($wormbase_seq,($f[1]-1),$span);
      $wormbase_len   = length ($wormbase_slice);
      $agp_len        = length ($EMBL_slice);
      
      # print log line
      printf AGPLOG "[%8d : %8d] %8s => Adding %6d bp from position %8d to %8d from version $EMBL_sv\n", $f[1],$f[2],$acc,$span,$from,$to;
      
      # add to consensus sequence
      $seq_con .= $EMBL_slice;
      
      # Sequence_version difference
      if ($sv =! $EMBL_sv) {
	print AGPLOG "ERROR: Discrepent sequence version for $acc [ACEDB:$sv <=> EMBL:$EMBL_sv\n";
      }
      
      # Sequence length difference
      if (length ($EMBL_slice) != $span) {
	print AGPLOG "ERROR: Discrepent no. of bases added for $acc [ACEDB:$span <=> EMBL:" . length ($EMBL_slice) . "\n";
      }
      
      # Sequence difference
      if ($EMBL_slice ne $wormbase_slice) {
	print AGPLOG "ERROR: you are not adding the same sequence for $acc\n"; 
	my ($count_a,$count_c,$count_g,$count_t,$count_n) = $wormbase->DNA_string_composition($wormbase_slice);
	print AGPLOG "ERROR: WormBase [$acc] : A=$count_a C=$count_c G=$count_g T=$count_t N=$count_n\n";
	($count_a,$count_c,$count_g,$count_t,$count_n) = $wormbase->DNA_string_composition($EMBL_slice);
	print AGPLOG "ERROR: EMBL     [$acc] : A=$count_a C=$count_c G=$count_g T=$count_t N=$count_n\n";
      }
    }
    # else insert gap 
    else {
      # print log line
      print AGPLOG "[$f[1] : $f[2]] Adding $f[5] bp of padding characters (sequence gap)\n";
      
      # add to consensus sequence
      $seq_con .= '-' x $f[5];
    }
  }
  close AGP;
  close AGPLOG;
  
  # write reconstructed sequence to file
  open (DNA, ">$logdir/CHROMOSOME_${chromosome}.agp.seq") || &usage(4);
  print DNA  ">CHROMOSOME_$chromosome\n";
  print DNA  "$seq_con\n";
  close DNA;
}

 ########################################
 # hasta luego                          #
 ########################################
$log->mail;
print "Finished.\n" if ($verbose);
exit(0);




 ########################################
 # getz query accession for sequence    #
 ########################################

sub sequence_getz {
    
    my $acc = shift;
    my ($EMBL_acc,$EMBL_sv,$EMBL_seq);
    
    open (SEQUENCE, "getz -d -sf fasta -f \'seqversion\' \"[{emblrelease emblnew}-acc:$acc] ! ([emblrelease-acc:$acc] < emblnew)\" |");
    while (<SEQUENCE>) {
	chomp;
        # deal with header line
 	if (/^SV\s+(\S+)\.(\d+)/) {
	    ($EMBL_acc,$EMBL_sv) = ($1,$2);
	    $EMBL_seq = "";
	    next;
	}
	next if (/^>/);
	$EMBL_seq .= $_;
    }
    close SEQUENCE;

    return($EMBL_acc,$EMBL_sv,$EMBL_seq);
}

sub sequence_pfetch {
    
    my $acc = shift;
    my ($EMBL_acc,$EMBL_sv,$EMBL_seq);
    
    open (SEQUENCE, "/usr/local/pubseq/bin/pfetch $acc |");
    while (<SEQUENCE>) {
	chomp;
	# deal with header line
	if (/>\S+\s+(\S+)\.(\d+)/) {
	    ($EMBL_acc,$EMBL_sv) = ($1,$2);
	    $EMBL_seq = "";
	    next;
	}
	# replace UPPER->lower case chars
	s/G/g/g;
	s/A/a/g;
	s/T/t/g;
	s/C/c/g;
	s/N/n/g;
	$EMBL_seq .= $_;
    }
    close SEQUENCE;

    return($EMBL_acc,$EMBL_sv,$EMBL_seq);
}


 ########################################
 # Usage and errors                     #
 ########################################

sub usage {
    my $error = shift;
    if ($error == "1"){ 
        # Error 01 - no DNA file to read
        $log->log_and_die("No Chromosome DNA file available.\n");
    }
    elsif ($error == 2){ 
        # Error 02 - no agp file to read
         $log->log_and_die("No Chromosome agp file available.\n");
    }
    elsif ($error == 3){ 
        # Error 03 - failed to open agp_seq.log file to write
         $log->log_and_die("Failed to open *.agp_seq.log file. Aborting run.\n");
    }
    elsif ($error == 4){ 
        # Error 04 - failed to open agp.seq file to write
         $log->log_and_die("Failed to open *.agp.seq file. Aborting run.\n");
    }
    elsif ($error == 5){ 
        # Error 05 - Single chromosome mode with invalid chromosome
        $log->log_and_die("Single chromosome mode aborted. '$chrom' is not a valid chromsome designation.\n");
    }
    elsif ($error eq "Help") {
	# Normal help menu
	exec ('perldoc',$0);
	exit(0)
    }

}

#################################################


__END__

=pod

=head2 NAME - agp2dna.pl

=head1 USAGE:

=over 4

=item agp2dna.pl [-options]

=back

agp2dna.pl mandatory arguments:

=over 4

=item none

=back

agp2dna.pl optional arguments:

=over 4

=item -chrom [txt], Single chromosome mode. Valid options (I,II,III,IV,V and X)

=item -pfetch, Retrieve sequence data using pfetch (default)

=item -getz, Retrieve sequence data using getz

=item -help, Help page

=item -debug, Verbose/Debug mode

=item -test, use test environment in ~wormpub/TEST_BUILD

=item -quicktest, as -test but only uses one chromosome for speed (CHROMOSOME III)

=back

=head1 RUN REQUIREMENTS:

agp2dna.pl requires a number of files:

CHROMOSOME_*.dna : DNA sequence for the chromosome [$basedir/autoace/CHROMOSOMES/]

CHROMOSOME_*.agp : agp file for the chromosome     [$basedir/autoace/CHROMOSOMES/]

=head1 EXAMPLES:

=over 4

=item agp2dna.pl 

=back

Reconstructs the chromosome sequences for all chromsomes using agp files from $basedir/autoace/CHROMOSOMES
and compares the sequence with the dna file in $basedir/autoace/CHROMOSOMES. The reconstructed dna file
and log files can be found in $basedir/autoace/yellow_brick_road

=over 4

=item agp2dna.pl -chrom I

=back

Reconstructs the chromosome sequences for chromsome I using agp file from $basedir/autoace/CHROMOSOMES
and compares the sequence with the dna file in $basedir/autoace/CHROMOSOMES. The reconstructed dna file
and log files can be found in $basedir/autoace/yellow_brick_road

=head1 AUTHOR:

Daniel Lawson : Email dl1@sanger.ac.uk

=cut
