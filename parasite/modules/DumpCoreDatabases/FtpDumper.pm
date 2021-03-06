package DumpCoreDatabases::FtpDumper;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::Process');
use File::Path qw(make_path remove_tree);
use File::Copy;

sub param_defaults {
  my ($self) = @_;

  return {
    %{$self->SUPER::param_defaults},
  };
}

sub run {
  my ($self) = @_;

#get options
  my $script = $self->param_required('script');
  my $params = $self->param('params');
  my $species = $self->param_required('species');
  my $out_dir = $self->param_required('out_dir');
  my $ps_rel = $self->param_required('ps_rel');
  my $suffix = $self->param_required('suffix');

#connect to core database and get info
  my $mc = Bio::EnsEMBL::Registry->get_adaptor($species, 'Core', 'MetaContainer');
  my $host     = $mc->dbc->host();
  my $port     = $mc->dbc->port();
  my $dbname = $mc->dbc->dbname();
  my ($sp) = ($dbname =~ /([^_]+_[^_]+)_.*?$/); 
  my $bioproject = 
    $mc->single_value_by_key('species.ftp_genome_id');
  $species =~ /[^_]+_[^_]+_([^_])/ and $bioproject //= $1;
  $mc->dbc->disconnect_if_idle();

#create directory structure
  my $dir = "$out_dir/$sp/$bioproject";
  make_path($dir);

#define file name
  my $prefix = "$sp.$bioproject.WBPS$ps_rel";
  my $out_file = "$dir/$prefix.$suffix";

  $params .= " --host $host";
  $params .= " --port $port";
  $params .= " --user ensro";
  $params .= " -dbname $dbname";
  $params .= " -outfile $out_file";

# disconnect from Hive - the script might be running for a while
  $self -> dbc && $self -> dbc -> disconnect_if_idle();

#call dump script
  my $command = "perl $script $params";

  unless (system($command) == 0) {
  	$self->throw("Failed to execute script: '$command'.");
  }

#path to file flows into next analysis
  $self->dataflow_output_id({out_file => $out_file}, 4);

}


1;
