#!/usr/local/bin/perl5.6.1 -w
#
# ChangeMethod.pl
#
# Last updated on: $Date: 2002-12-09 14:20:18 $
# Last updated by: $Author: krb $

# Script to change the method associated with each gene
# Only two methods will be conserved: provisional and confirmed
# Skips tRNA genes, etc ..

use strict;
use lib "/wormsrv2/scripts/";
use Wormbase;
use Ace;
use Getopt::Std;
$|=1;

getopts ('d:');

# Create touch file to record script activity
$0 =~ m/\/*([^\/]+)$/; system ("touch /wormsrv2/logs/history/$1.`date +%y%m%d`");

$HELP=<<END;

ChangeMethod will change the method asociated
with each gene from anything to provisional
and confirmed. Usage:

ChangeMethod -d dbname

dbname will be one of the following: cgcace, autoace, camace

END

if (!$opt_d){
print $HELP;
}
if (($opt_d !~ /cgcace/)||($opt_d !~ /autoace/)||($opt_d !~ /camace/)) {
  print $HELP;
}

# cgcace => port 210203
# autoace => port 210202
# camace => port 100100

if ($opt_d =~ /cgcace/) {$port="210203"};
if ($opt_d =~ /autoace/) {$port="210202"};
if ($opt_d =~ /camace/) {$port="100100"};

$db = Ace->connect(-host=>'wormsrv1',-port=>'$port') or die ("Can not connect with database");
print "Database connection successful\n\n";

# Retrieve all the Genome sequences from database
# and extracts subsequences
# Will not retrieve subsequences with source = LINK *
$i = $db->fetch_many(Genome_sequence,"*");  
while ($obj = $i->next) {
  $project = $obj;
  @subseqs = $project->at('Structure.Subsequence');
  foreach (@subseqs) {
    $name = $_;
    chomp $name;
    if ($name =~ /\.PF\w+\./) {
      next;
    }
    if ($name =~ /\.gw\./) {
      next;
    }
    if ($name =~ /\.\d+$/) {
      print "$name is a CONFIRMED GENE\n";
      $gene=$db->fetch(Sequence=>$name);
      $method=$gene->at("Method[1]");
      print "Metod for ${gene} : $method\n";
      if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
      if ($method =~ /Transposon/) {print "Transposon\n"; next;}
      if ($method =~ /curated/) {next;}
      if ($method =~ /provisional/) {next;}
      $result = $gene->replace("Method",$method,"curated");
      print "# Replace RESULT is $result\n";
      $gene->commit;
      print Ace->error;
      print "\n";      
    } 
    elsif ($name =~ /\.\d+\D+$/) {
      print "$name is an ALTERNATIVE SPLICE\n";
      $gene=$db->fetch(Sequence=>$name);
      $method=$gene->at("Method[1]");
      print "Metod for ${gene} : $method\n";
      if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
      if ($method =~ /Transposon/) {print "Transposon\n"; next;}
      if ($method =~ /curated/) {next;}
      if ($method =~ /provisional/) {next;}
      $result = $gene->replace("Method",$method,"curated");
      print "# Replace RESULT with curated is $result\n";
      $gene->commit;
      print Ace->error;
      print "\n";      
    }	elsif ($name =~ /\.\D+$/) {
      print "$name is a PROVISIONAL GENE\n";
      $gene=$db->fetch(Sequence=>$name);
      $method=$gene->at("Method[1]");
      print "Metod for ${gene} : $method\n";
      if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
      if ($method =~ /Transposon/) {print "Transposon\n"; next;}
      if ($method =~ /curated/) {next;}
      if ($method =~ /provisional/) {next;}
      $result = $gene->replace("Method",$method,"provisional");	
      print "#Replace RESULT with provisional is $result\n";
      $gene->commit;
      print Ace->error;
      print "\n";
    } else {
      print "$name is a trna gene\n";
      $gene=$db->fetch(Sequence=>$name);
      $method=$gene->at("Method[1]");
      print "Metod for ${gene} : $method\n";
      if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
      if ($method =~ /Transposon/) {print "Transposon\n"; next;}
      if ($method =~ /curated/) {next;}
      if ($method =~ /provisional/) {next;}
      if ($method =~ /tRNAscan/) {next;}
      $result = $gene->replace("Method",$method,"tRNAscan-SE-1.11");	
      print "#Replace RESULT with tRNAscan is $result\n";
      $gene->commit;
      print Ace->error;
      print "\n";
    }
  }
}

# Retrieve all the sequences with source = LINK*
# Consider only subsequences and change as above

# Corresponding AQL query is :
# $query = "aql select a, a->Source from a in class Sequence where a->Source like \"LINK*\" ";

$z = $db->fetch_many(Sequence,"*");  
while ($seq = $z->next) {
  $name = "${seq}"; 
  if ($name !~ /\.\w+/) {next;}
  if ($name =~ /\.PF/) {next;}
  $source = $seq->at('Structure.From.Source[1]');
  if ($source =~ /LINK/) {
    print "Seqname is $name Source is $source\n";    
    push (@seqnames,$name);
  } else {
    next;
  }
}

# We have to do this loop because looks like Aceperl does not like
# modifiying the same sequence he is actually reading
foreach (@seqnames) {
  $genename=$_;
  chomp $genename;
  print "Currently checking $genename\n";
  if ($genename =~ /\.\d+$/) {
    print "$genename is a CONFIRMED GENE\n";
    $gene=$db->fetch(Sequence=>$genename);
    $method=$gene->at("Method[1]");
    print "Metod for ${gene} : $method\n";
    if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
    if ($method =~ /Transposon/) {print "Transposon\n"; next;}
    if ($method =~ /curated/) {next;}
    if ($method =~ /provisional/) {next;}
    $result = $gene->replace("Method",$method,"curated");
    print "#Replace RESULT with curated is $result\n";
    $gene->commit;
    print Ace->error;
    print "\n";      
  } 
  elsif ($genename =~ /\.\d+\D+$/) {
    print "$genename is an ALTERNATIVE SPLICE\n";
    $gene=$db->fetch(Sequence=>$genename);
    $method=$gene->at("Method[1]");
    print "Metod for ${gene} : $method\n";
    if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
    if ($method =~ /Transposon/) {print "Transposon\n"; next;}
    if ($method =~ /curated/) {next;}
    if ($method =~ /provisional/) {next;}
    $result = $gene->replace("Method",$method,"curated");
    print "#Replace RESULT with curated is $result\n";
    $gene->commit;
    print Ace->error;
    print "\n";      
  }	
  elsif ($genename =~ /\.\D+$/) {
    print "$genename is a PROVISIONAL GENE\n";
    $gene=$db->fetch(Sequence=>$genename);
    $method=$gene->at("Method[1]");
    print "Metod for ${gene} : $method\n";
    if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
    if ($method =~ /Transposon/) {print "Transposon\n"; next;}
    if ($method =~ /curated/) {next;}
    if ($method =~ /provisional/) {next;}
    $result = $gene->replace("Method",$method,"provisional");	
    print "#Replace RESULT with provisonal is $result\n";
    $gene->commit;
    print Ace->error;
    print "\n";
  } 
  else {
    print "$name is a trna gene\n";
    $gene=$db->fetch(Sequence=>$genename);
    $method=$gene->at("Method[1]");
    print "Metod for ${gene} : $method\n";
    if ($method =~ /Pseudogene/) {print "Pseudogene\n"; next;}
    if ($method =~ /Transposon/) {print "Transposon\n"; next;}
    if ($method =~ /curated/) {next;}
    if ($method =~ /provisional/) {next;}
    if ($method =~ /tRNAscan/) {next;}
    $result = $gene->replace("Method",$method,"tRNAscan-SE-1.11");	
    print "# RESULT is $result\n";
    $gene->commit;
    print Ace->error;
    print "\n";
  }    
}

print "ChangeMetod FINISHED \n\n";
$db->close;
exit(0);
