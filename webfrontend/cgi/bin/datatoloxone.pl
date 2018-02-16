#!/usr/bin/perl

# Copyright 2016 Michael Schlenstedt, michael@loxberry.de
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

##########################################################################
# Modules
##########################################################################

use Getopt::Long;
use IO::Socket; # For sending UDP packages
use DateTime;
use File::HomeDir;
use Cwd 'abs_path';
use Config::Simple;
use LWP::UserAgent;

#use strict;
#use warnings;

##########################################################################
# Read settings
##########################################################################

# Figure out in which subfolder we are installed
our $psubfolder = abs_path($0);
$psubfolder =~ s/(.*)\/(.*)\/bin\/(.*)$/$2/g;
our $home = File::HomeDir->my_home;
our $webpath = "/plugins/$psubfolder";

# Version of this script
my $version = "4.0.3";

our $pcfg             = new Config::Simple("$home/config/plugins/$psubfolder/wu4lox.cfg");
my  $udpport          = $pcfg->param("SERVER.UDPPORT");
my  $senddfc          = $pcfg->param("SERVER.SENDDFC");
my  $sendhfc          = $pcfg->param("SERVER.SENDHFC");
our $sendudp          = $pcfg->param("SERVER.SENDUDP");
our $metric           = $pcfg->param("SERVER.METRIC");
our $emu              = $pcfg->param("SERVER.EMU");
our $stdtheme         = $pcfg->param("WEB.THEME");
our $stdiconset       = $pcfg->param("WEB.ICONSET");

our $cfg              = new Config::Simple("$home/config/system/general.cfg");
my  $installfolder    = $cfg->param("BASE.INSTALLFOLDER");
my  $miniservers      = $cfg->param("BASE.MINISERVERS");
my  $clouddns         = $cfg->param("BASE.CLOUDDNS");
my  $lang             = $cfg->param("BASE.LANG");

# Commandline options
my $verbose = '';
my $help = '';

GetOptions ('verbose' => \$verbose,
                'quiet'   => sub { $verbose = 0 });

##########################################################################
# Main program
##########################################################################

my $i;

# Starting...
my $logmessage = "<INFO> Starting $0 Version $version\n";
&log;

# Clear HTML databse
open(F,">$home/webfrontend/html/plugins/$psubfolder/weatherdata.html") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/weatherdata.html";
  print F "";
close(F);

# Date Reference: Convert into Loxone Epoche (1.1.2009)
my $dateref = DateTime->new(
      year      => 2009,
      month     => 1,
      day       => 1,
);

# UDP Queue Limits
our $sendqueue = 0;
our $sendqueuelimit = 50;

# If we should send by UDP, figure out which Miniservers are configured
if ($sendudp) {

  for ($i=1;$i<=$miniservers;$i++) {

    ${miniservername . "$i"} = $cfg->param("MINISERVER$i.NAME");

    if ( $cfg->param("MINISERVER$i.USECLOUDDNS") ) {
      my $miniservermac = $cfg->param("MINISERVER$i.CLOUDURL");
      my $dns_info = `$home/webfrontend/cgi/system/tools/showclouddns.pl $miniservermac`;
      my @dns_info_pieces = split /:/, $dns_info;
      if ($dns_info_pieces[0]) {
        $dns_info_pieces[0] =~ s/^\s+|\s+$//g;
        ${miniserverip . "$i"} = $dns_info_pieces[0]; 
        $logmessage = "<INFO> Send Data to " . ${miniservername . "$i"} . " at " . ${miniserverip . "$i"} . " using CloudDNS.\n";
        &log;
      } else {
        ${miniserverip . "$i"} = "127.0.0.1"; 
        $logmessage = "<ERROR> Could not find IP Address for " . ${miniservername . "$i"} . " using CloudDNS.\n";
        &log;
      }
    } else {
      if ( $cfg->param("MINISERVER$i.IPADDRESS") ) {
        ${miniserverip . "$i"} = $cfg->param("MINISERVER$i.IPADDRESS");
        $logmessage = "<INFO> Send Data to " . ${miniservername . "$i"}  . " at " . ${miniserverip . "$i"} . ".\n";
        &log;
      } else {
        ${miniserverip . "$i"} = "127.0.0.1"; 
        $logmessage = "<ERROR> Could not find IP Address for " . ${miniservername . "$i"} . ".\n";
        &log;
      }
    }
    
  }

}

#
# Print out current conditions
#

# Read data
open(F,"<$home/data/plugins/$psubfolder/current.dat") || die "Cannot open $home/data/plugins/$psubfolder/current.dat";
  our $curdata = <F>;
close(F);

chomp $curdata;

my @fields = split(/\|/,$curdata);
our $value;
our $name;
our $tmpudp;
our $udp;

# Check for empty data
if (@fields[0] eq "") {
  @fields[0] = 1230764400;
  @fields[34] = 0;
  @fields[35] = 0;
  @fields[36] = 0;
  @fields[37] = 0;
}

# Correct Epoch by Timezone
$tzseconds = (@fields[4] / 100 * 3600);

# EpochDate - Corrected by TZ
our $epochdate = DateTime->from_epoch(
      epoch      => @fields[0],
);
$epochdate->add( seconds => $tzseconds );

$name = "cur_date";
$value = @fields[0] - $dateref->epoch() + (@fields[4] / 100 * 3600);
&send;

$name = "cur_date_des";
$value = @fields[1];
#&send;

$name = "cur_date_tz_des_sh";
$value = @fields[2];
#&send;

$name = "cur_date_tz_des";
$value = @fields[3];
#&send;

$name = "cur_date_tz";
$value = @fields[4];
#&send;

$name = "cur_day";
$value = $epochdate->day;
&send;

$name = "cur_month";
$value = $epochdate->month;
&send;

$name = "cur_year";
$value = $epochdate->year;
&send;

$name = "cur_hour";
$value = $epochdate->hour;
&send;

$name = "cur_min";
$value = $epochdate->minute;
&send;

$name = "cur_loc_n";
$value = @fields[5];
#&send;

$name = "cur_loc_c";
$value = @fields[6];
#&send;

$name = "cur_loc_ccode";
$value = @fields[7];
#&send;

$name = "cur_loc_lat";
$value = @fields[8];
&send;

$name = "cur_loc_long";
$value = @fields[9];
&send;

$name = "cur_loc_el";
$value = @fields[10];
&send;

$name = "cur_tt";
if (!$metric) {$value = @fields[11]*1.8+32} else {$value = @fields[11]};
&send;

$name = "cur_tt_fl";
if (!$metric) {$value = @fields[12]*1.8+32} else {$value = @fields[12]};
&send;

$name = "cur_hu";
$value = @fields[13];
&send;

$name = "cur_w_dirdes";
$value = @fields[14];
#&send;

$name = "cur_w_dir";
$value = @fields[15];
&send;

$name = "cur_w_sp";
if (!$metric) {$value = @fields[16]*0.621371192} else {$value = @fields[16]};
&send;

$name = "cur_w_gu";
if (!$metric) {$value = @fields[17]*0.621371192} else {$value = @fields[17]};
&send;

$name = "cur_w_ch";
if (!$metric) {$value = @fields[18]*1.8+32} else {$value = @fields[18]};
&send;

$name = "cur_pr";
if (!$metric) {$value = @fields[19]*0.0295301} else {$value = @fields[19]};
&send;

$name = "cur_dp";
if (!$metric) {$value = @fields[20]*1.8+32} else {$value = @fields[20]};
&send;

$name = "cur_vis";
if (!$metric) {$value = @fields[21]*0.621371192} else {$value = @fields[21]};
&send;

$name = "cur_sr";
$value = @fields[22];
&send;

$name = "cur_hi";
if (!$metric) {$value = @fields[23]*1.8+32} else {$value = @fields[23]};
&send;

$name = "cur_uvi";
$value = @fields[24];
&send;

$name = "cur_prec_today"; 
if (!$metric) {$value = @fields[25]*0.0393700787} else {$value = @fields[25]};
&send;

$name = "cur_prec_1hr"; 
if (!$metric) {$value = @fields[26]*0.0393700787} else {$value = @fields[26]};
&send;

$name = "cur_we_icon"; 
$value = @fields[27];
#&send;

$name = "cur_we_code"; 
$value = @fields[28];
&send;

$name = "cur_we_des"; 
$value = @fields[29];
#&send;

$name = "cur_moon_p"; 
$value = @fields[30];
&send;

$name = "cur_moon_a"; 
$value = @fields[31];
&send;

$name = "cur_moon_ph"; 
$value = @fields[32];
#&send;

$name = "cur_moon_h"; 
$value = @fields[33];
#&send;

# Create Sunset/rise Date in Loxone Epoch Format (1.1.2009)
# Sunrise
my $sunrdate = DateTime->new(
      year      => $epochdate -> year(),
      month     => $epochdate -> month(),
      day       => $epochdate -> day(),
      hour      => @fields[34],
      minute    => @fields[35],
);
#$sunrdate->add( seconds => $tzseconds );

# Sunset
my $sunsdate = DateTime->new(
      year      => $epochdate -> year(),
      month     => $epochdate -> month(),
      day       => $epochdate -> day(),
      hour      => @fields[36],
      minute    => @fields[37],
);
#$sunsdate->add( seconds => $tzseconds );

$name = "cur_sun_r";
$value = $sunrdate->epoch() - $dateref->epoch();
&send;

$name = "cur_sun_s";
$value = $sunsdate->epoch() - $dateref->epoch();
$udp = 1; # Really send now in one run
&send;

#
# Print out Daily Forecast
#

# Read data
open(F,"<$home/data/plugins/$psubfolder/dailyforecast.dat") || die "Cannot open $home/data/plugins/$psubfolder/dailyforecast.dat";
  our @dfcdata = <F>;
close(F);

foreach (@dfcdata){
  s/[\n\r]//g;
  my @fields = split(/\|/);

  my $per = @fields[0];

  # Send values only if we should do so
  my $send = 0;
  foreach (split(/;/,$senddfc)){
    if ($_ eq $per) {
      $send = 1;
    }
  }
  if (!$send) {
    next;
  }

  # DFC: Today is dfc0
  $per = $per-1;

  # Check for empty data
  if (@fields[1] eq "") {
    @fields[1] = 1230764400;
  }

  $name = "dfc$per\_per";
  $value = $per;
  &send;

  $name = "dfc$per\_date";
  $value = @fields[1] - $dateref->epoch();
  &send;

  $name = "dfc$per\_day";
  $value = @fields[2];
  &send;

  $name = "dfc$per\_month";
  $value = @fields[3];
  &send;

  $name = "dfc$per\_monthn";
  $value = @fields[4];
#  &send;

  $name = "dfc$per\_monthn_sh";
  $value = @fields[5];
#  &send;

  $name = "dfc$per\_year";
  $value = @fields[6];
  &send;

  $name = "dfc$per\_hour";
  $value = @fields[7];
  &send;

  $name = "dfc$per\_min";
  $value = @fields[8];
  &send;

  $name = "dfc$per\_wday";
  $value = @fields[9];
#  &send;

  $name = "dfc$per\_wday_sh";
  $value = @fields[10];
#  &send;

  $name = "dfc$per\_tt_h";
  if (!$metric) {$value = @fields[11]*1.8+32} else {$value = @fields[11];}
  &send;

  $name = "dfc$per\_tt_l";
  if (!$metric) {$value = @fields[12]*1.8+32} else {$value = @fields[12];}
  &send;

  $name = "dfc$per\_pop";
  $value = @fields[13];
  &send;

  $name = "dfc$per\_prec";
  if (!$metric) {$value = @fields[14]*0.0393700787} else {$value = @fields[14];}
  &send;

  $name = "dfc$per\_snow";
  if (!$metric) {$value = @fields[15]*0.393700787} else {$value = @fields[15];}
  &send;

  $name = "dfc$per\_w_sp_h";
  if (!$metric) {$value = @fields[16]*0.621} else {$value = @fields[16];}
  &send;

  $name = "dfc$per\_w_dirdes_h";
  $value = @fields[17];
#  &send;

  $name = "dfc$per\_w_dir_h";
  $value = @fields[18];
  &send;

  $name = "dfc$per\_w_sp_a";
  if (!$metric) {$value = @fields[19]*0.621} else {$value = @fields[19];}
  &send;

  $name = "dfc$per\_w_dirdes_a";
  $value = @fields[20];
#  &send;

  $name = "dfc$per\_w_dir_a";
  $value = @fields[21];
  &send;

  $name = "dfc$per\_hu_a";
  $value = @fields[22];
  &send;

  $name = "dfc$per\_hu_h";
  $value = @fields[23];
  &send;

  $name = "dfc$per\_hu_l";
  $value = @fields[24];
  &send;

  $name = "dfc$per\_we_icon";
  $value = @fields[25];
#  &send;

  $name = "dfc$per\_we_code";
  $value = @fields[26];
  $udp = 1; # Really send now in one run
  &send;

  $name = "dfc$per\_we_des";
  $value = @fields[27];
#  &send;

}

#
# Print out Hourly Forecast
#

# Read data
open(F,"<$home/data/plugins/$psubfolder/hourlyforecast.dat") || die "Cannot open $home/data/plugins/$psubfolder/hourlyforecast.dat";
  our @hfcdata = <F>;
close(F);

foreach (@hfcdata){
  s/[\n\r]//g;
  my @fields = split(/\|/);

  my $per = @fields[0];

  # Send values only if we should do so
  my $send = 0;
  foreach (split(/;/,$sendhfc)){
    if ($_ eq $per) {
      $send = 1;
    }
  }
  if (!$send) {
    next;
  }

  # Check for empty data
  if (@fields[1] eq "") {
    @fields[1] = 1230764400;
  }

  $name = "hfc$per\_per";
  $value = @fields[0];
  &send;

  $name = "hfc$per\_date";
  $value = @fields[1] - $dateref->epoch();
  &send;

  $name = "hfc$per\_day";
  $value = @fields[2];
  &send;

  $name = "hfc$per\_month";
  $value = @fields[3];
  &send;

  $name = "hfc$per\_monthn";
  $value = @fields[4];
#  &send;

  $name = "hfc$per\_monthn_sh";
  $value = @fields[5];
#  &send;

  $name = "hfc$per\_year";
  $value = @fields[6];
  &send;

  $name = "hfc$per\_hour";
  $value = @fields[7];
  &send;

  $name = "hfc$per\_min";
  $value = @fields[8];
  &send;

  $name = "hfc$per\_wday";
  $value = @fields[9];
#  &send;

  $name = "hfc$per\_wday_sh";
  $value = @fields[10];
#  &send;

  $name = "hfc$per\_tt";
  if (!$metric) {$value = @fields[11]*1.8+32} else {$value = @fields[11];}
  &send;

  $name = "hfc$per\_tt_fl";
  if (!$metric) {$value = @fields[12]*1.8+32} else {$value = @fields[12];}
  &send;

  $name = "hfc$per\_hi";
  if (!$metric) {$value = @fields[13]*1.8+32} else {$value = @fields[13];}
  &send;

  $name = "hfc$per\_hu";
  $value = @fields[14];
  &send;

  $name = "hfc$per\_w_dirdes";
  $value = @fields[15];
#  &send;

  $name = "hfc$per\_w_dir";
  $value = @fields[16];
  &send;

  $name = "hfc$per\_w_sp";
  if (!$metric) {$value = @fields[17]*0.621} else {$value = @fields[17];}
  &send;

  $name = "hfc$per\_w_ch";
  if (!$metric) {$value = @fields[18]*1.8+32} else {$value = @fields[18]};
  &send;

  $name = "hfc$per\_pr";
  $value = @fields[19];
  &send;

  $name = "hfc$per\_dp";
  $value = @fields[20];
  &send;

  $name = "hfc$per\_sky";
  $value = @fields[21];
  &send;

  $name = "hfc$per\_sky\_des";
  $value = @fields[22];
#  &send;

  $name = "hfc$per\_uvi";
  $value = @fields[23];
  &send;

  $name = "hfc$per\_prec";
  if (!$metric) {$value = @fields[24]*0.0393700787} else {$value = @fields[24];}
  &send;

  $name = "hfc$per\_snow";
  if (!$metric) {$value = @fields[25]*0.393700787} else {$value = @fields[25];}
  &send;

  $name = "hfc$per\_pop";
  $value = @fields[26];
  &send;

  $name = "hfc$per\_we_code";
  $value = @fields[27];
  $udp = 1; # Really send now in one run
  &send;

  $name = "hfc$per\_we_icon";
  $value = @fields[28];
#  &send;


  $name = "hfc$per\_we_des";
  $value = @fields[29];
#  &send;

}

#
# Print out calculated Forecast values
#

# Prec within the next hours
my $tmpprec4 = 0;
my $tmpprec8 = 0;
my $tmpprec16 = 0;
my $tmpprec24 = 0;
my $tmpprec32 = 0;
my $tmpprec40 = 0;
my $tmpprec48 = 0;

# Snow within the next hours
my $tmpsnow4 = 0;
my $tmpsnow8 = 0;
my $tmpsnow16 = 0;
my $tmpsnow24 = 0;
my $tmpsnow32 = 0;
my $tmpsnow40 = 0;
my $tmpsnow48 = 0;

# Min Temp within the next hours
my $tmpttmin4 = 0;
my $tmpttmin8 = 0;
my $tmpttmin16 = 0;
my $tmpttmin24 = 0;
my $tmpttmin32 = 0;
my $tmpttmin40 = 0;
my $tmpttmin48 = 0;

# Max Temp within the next hours
my $tmpttmax4 = 0;
my $tmpttmax8 = 0;
my $tmpttmax16 = 0;
my $tmpttmax24 = 0;
my $tmpttmax32 = 0;
my $tmpttmax40 = 0;
my $tmpttmax48 = 0;

# Min Pop within the next hours
my $tmppopmin4 = 0;
my $tmppopmin8 = 0;
my $tmppopmin16 = 0;
my $tmppopmin24 = 0;
my $tmppopmin32 = 0;
my $tmppopmin40 = 0;
my $tmppopmin48 = 0;

# Max Pop within the next hours
my $tmppopmax4 = 0;
my $tmppopmax8 = 0;
my $tmppopmax16 = 0;
my $tmppopmax24 = 0;
my $tmppopmax32 = 0;
my $tmppopmax40 = 0;
my $tmppopmax48 = 0;

foreach (@hfcdata){
  s/[\n\r]//g;
  my @fields = split(/\|/);

  # Default values for min/max
  if ( @fields[0] == 1 ) {
      $tmpttmax4 = @fields[11];
      $tmpttmin4 = @fields[11];
      $tmpttmax8 = @fields[11];
      $tmpttmin8 = @fields[11];
      $tmpttmax16 = @fields[11];
      $tmpttmin16 = @fields[11];
      $tmpttmax24 = @fields[11];
      $tmpttmin24 = @fields[11];
      $tmpttmax32 = @fields[11];
      $tmpttmin32 = @fields[11];
      $tmpttmax40 = @fields[11];
      $tmpttmin40 = @fields[11];
      $tmpttmax48 = @fields[11];
      $tmpttmin48 = @fields[11];

      $tmppopmax4 = @fields[26];
      $tmppopmin4 = @fields[26];
      $tmppopmax8 = @fields[26];
      $tmppopmin8 = @fields[26];
      $tmppopmax16 = @fields[26];
      $tmppopmin16 = @fields[26];
      $tmppopmax24 = @fields[26];
      $tmppopmin24 = @fields[26];
      $tmppopmax32 = @fields[26];
      $tmppopmin32 = @fields[26];
      $tmppopmax40 = @fields[26];
      $tmppopmin40 = @fields[26];
      $tmppopmax48 = @fields[26];
      $tmppopmin48 = @fields[26];
  }
  if ( @fields[0] <= 4 ) {
    $tmpprec4 .+ @fields[24];
    $tmpsnow4 .+ @fields[25];
    if ( $tmpttmin4 > @fields[11] ) { $tmpttmin4 = @fields[11]; }
    if ( $tmpttmax4 < @fields[11] ) { $tmpttmax4 = @fields[11]; }
    if ( $tmppopmin4 > @fields[26] ) { $tmppopmin4 = @fields[26]; }
    if ( $tmppopmax4 < @fields[26] ) { $tmppopmax4 = @fields[26]; }
  } 
  if ( @fields[0] <= 8 ) {
    $tmpprec8 .+ @fields[24];
    $tmpsnow8 .+ @fields[25];
    if ( $tmpttmin8 > @fields[11] ) { $tmpttmin8 = @fields[11]; }
    if ( $tmpttmax8 < @fields[11] ) { $tmpttmax8 = @fields[11]; }
    if ( $tmppopmin8 > @fields[26] ) { $tmppopmin8 = @fields[26]; }
    if ( $tmppopmax8 < @fields[26] ) { $tmppopmax8 = @fields[26]; }
  } 
  if ( @fields[0] <= 16 ) {
    $tmpprec16 .+ @fields[24];
    $tmpsnow16 .+ @fields[25];
    if ( $tmpttmin16 > @fields[11] ) { $tmpttmin16 = @fields[11]; }
    if ( $tmpttmax16 < @fields[11] ) { $tmpttmax16 = @fields[11]; }
    if ( $tmppopmin16 > @fields[26] ) { $tmppopmin16 = @fields[26]; }
    if ( $tmppopmax16 < @fields[26] ) { $tmppopmax16 = @fields[26]; }
  } 
  if ( @fields[0] <= 24 ) {
    $tmpprec24 .+ @fields[24];
    $tmpsnow24 .+ @fields[25];
    if ( $tmpttmin24 > @fields[11] ) { $tmpttmin24 = @fields[11]; }
    if ( $tmpttmax24 < @fields[11] ) { $tmpttmax24 = @fields[11]; }
    if ( $tmppopmin24 > @fields[26] ) { $tmppopmin24 = @fields[26]; }
    if ( $tmppopmax24 < @fields[26] ) { $tmppopmax24 = @fields[26]; }
  } 
  if ( @fields[0] <= 32 ) {
    $tmpprec32 .+ @fields[24];
    $tmpsnow32 .+ @fields[25];
    if ( $tmpttmin32 > @fields[11] ) { $tmpttmin32 = @fields[11]; }
    if ( $tmpttmax32 < @fields[11] ) { $tmpttmax32 = @fields[11]; }
    if ( $tmppopmin32 > @fields[26] ) { $tmppopmin32 = @fields[26]; }
    if ( $tmppopmax32 < @fields[26] ) { $tmppopmax32 = @fields[26]; }
  } 
  if ( @fields[0] <= 40 ) {
    $tmpprec40 .+ @fields[24];
    $tmpsnow40 .+ @fields[25];
    if ( $tmpttmin40 > @fields[11] ) { $tmpttmin40 = @fields[11]; }
    if ( $tmpttmax40 < @fields[11] ) { $tmpttmax40 = @fields[11]; }
    if ( $tmppopmin40 > @fields[26] ) { $tmppopmin40 = @fields[26]; }
    if ( $tmppopmax40 < @fields[26] ) { $tmppopmax40 = @fields[26]; }
  } 
  if ( @fields[0] <= 48 ) {
    $tmpprec48 .+ @fields[24];
    $tmpsnow48 .+ @fields[25];
    if ( $tmpttmin48 > @fields[11] ) { $tmpttmin48 = @fields[11]; }
    if ( $tmpttmax48 < @fields[11] ) { $tmpttmax48 = @fields[11]; }
    if ( $tmppopmin48 > @fields[26] ) { $tmppopmin48 = @fields[26]; }
    if ( $tmppopmax48 < @fields[26] ) { $tmppopmax48 = @fields[26]; }
  } 

}

# Add calculated to send queue

# ttmax
$name = "calc+4\_ttmax";
$value = $tmpttmax4;
&send;
$name = "calc+8\_ttmax";
$value = $tmpttmax8;
&send;
$name = "calc+16\_ttmax";
$value = $tmpttmax16;
&send;
$name = "calc+24\_ttmax";
$value = $tmpttmax24;
&send;
$name = "calc+32\_ttmax";
$value = $tmpttmax32;
&send;
$name = "calc+40\_ttmax";
$value = $tmpttmax40;
&send;
$name = "calc+48\_ttmax";
$value = $tmpttmax48;
&send;

# ttmin
$name = "calc+4\_ttmin";
$value = $tmpttmin4;
&send;
$name = "calc+8\_ttmin";
$value = $tmpttmin8;
&send;
$name = "calc+16\_ttmin";
$value = $tmpttmin16;
&send;
$name = "calc+24\_ttmin";
$value = $tmpttmin24;
&send;
$name = "calc+32\_ttmin";
$value = $tmpttmin32;
&send;
$name = "calc+40\_ttmin";
$value = $tmpttmin40;
&send;
$name = "calc+48\_ttmin";
$value = $tmpttmin48;
&send;

# popmax
$name = "calc+4\_popmax";
$value = $tmppopmax4;
&send;
$name = "calc+8\_popmax";
$value = $tmppopmax8;
&send;
$name = "calc+16\_popmax";
$value = $tmppopmax16;
&send;
$name = "calc+24\_popmax";
$value = $tmppopmax24;
&send;
$name = "calc+32\_popmax";
$value = $tmppopmax32;
&send;
$name = "calc+40\_popmax";
$value = $tmppopmax40;
&send;
$name = "calc+48\_popmax";
$value = $tmppopmax48;
&send;

# popmin
$name = "calc+4\_popmin";
$value = $tmppopmin4;
&send;
$name = "calc+8\_popmin";
$value = $tmppopmin8;
&send;
$name = "calc+16\_popmin";
$value = $tmppopmin16;
&send;
$name = "calc+24\_popmin";
$value = $tmppopmin24;
&send;
$name = "calc+32\_popmin";
$value = $tmppopmin32;
&send;
$name = "calc+40\_popmin";
$value = $tmppopmin40;
&send;
$name = "calc+48\_popmin";
$value = $tmppopmin48;
&send;

# prec
$name = "calc+4\_prec";
$value = $tmpprec4;
&send;
$name = "calc+8\_prec";
$value = $tmpprec8;
&send;
$name = "calc+16\_prec";
$value = $tmpprec16;
&send;
$name = "calc+24\_prec";
$value = $tmpprec24;
&send;
$name = "calc+32\_prec";
$value = $tmpprec32;
&send;
$name = "calc+40\_prec";
$value = $tmpprec40;
&send;
$name = "calc+48\_prec";
$value = $tmpprec48;
&send;

# snow
$name = "calc+4\_snow";
$value = $tmpsnow4;
&send;
$name = "calc+8\_snow";
$value = $tmpsnow8;
&send;
$name = "calc+16\_snow";
$value = $tmpsnow16;
&send;
$name = "calc+24\_snow";
$value = $tmpsnow24;
&send;
$name = "calc+32\_snow";
$value = $tmpsnow32;
&send;
$name = "calc+40\_snow";
$value = $tmpsnow40;
&send;
$name = "calc+48\_snow";
$value = $tmpsnow48;
&send;

$udp = 1; # Really send now in one run

#
# Create Webpages
#

$logmessage = "<INFO> Creating Webpages...\n";
&log;

$theme = $stdtheme;
$iconset = $stdiconset;
$themeurlmain = "./webpage.html";
$themeurldfc = "./webpage.dfc.html";
$themeurlhfc = "./webpage.hfc.html";
$themeurlmap = "./webpage.map.html";

# Date Reference: Convert into Loxone Epoche (1.1.2009)
my $dateref = DateTime->new(
      year      => 2009,
      month     => 1,
      day       => 1,
      time_zone => 'local',
);

#############################################
# CURRENT CONDITIONS
#############################################

# Get current weather data from database
open(F,"<$home/data/plugins/$psubfolder/current.dat") || die "Cannot open $home/data/plugins/$psubfolder/current.dat";
  our $curdata = <F>;
close(F);

chomp $curdata;

my @fields = split(/\|/,$curdata);

$cur_date = @fields[0];
$cur_date_des = @fields[1];
$cur_date_tz_des_sh = @fields[2];
$cur_date_tz_des = @fields[3];
$cur_date_tz = @fields[4];

our $epochdate = DateTime->from_epoch(
      epoch      => @fields[0],
      time_zone => 'local',
);

$cur_day        = sprintf("%02d", $epochdate->day);
$cur_month      = sprintf("%02d", $epochdate->month);
$cur_hour       = sprintf("%02d", $epochdate->hour);
$cur_min        = sprintf("%02d", $epochdate->minute);
$cur_year       = $epochdate->year;
$cur_loc_n      = @fields[5];
$cur_loc_c      = @fields[6];
$cur_loc_ccode  = @fields[7];
$cur_loc_lat    = @fields[8];
$cur_loc_long   = @fields[9];
$cur_loc_el     = @fields[10];
$cur_hu         = @fields[13];
$cur_w_dirdes   = @fields[14];
$cur_w_dir      = @fields[15];
$cur_sr         = @fields[22];
$cur_uvi        = @fields[24];
$cur_we_icon    = @fields[27];
$cur_we_code    = @fields[28];
$cur_we_des     = @fields[29];
$cur_moon_p     = @fields[30];
$cur_moon_a     = @fields[31];
$cur_moon_ph    = @fields[32];
$cur_moon_h     = @fields[33];

if (!$metric) {
$cur_tt         = @fields[11]*1.8+32;
$cur_tt_fl      = @fields[12]*1.8+32;
$cur_w_sp       = @fields[16]*0.621371192;
$cur_w_gu       = @fields[17]*0.621371192;
$cur_w_ch       = @fields[18]*1.8+32;
$cur_pr         = @fields[19]*0.0295301;
$cur_dp         = @fields[20]*1.8+32;
$cur_vis        = @fields[21]*0.621371192;
$cur_hi         = @fields[23]*1.8+32;
$cur_prec_today = @fields[25]*0.0393700787;
$cur_prec_1hr   = @fields[26]*0.0393700787;
} else {
$cur_tt         = @fields[11];
$cur_tt_fl      = @fields[12];
$cur_w_sp       = @fields[16];
$cur_w_gu       = @fields[17];
$cur_w_ch       = @fields[18];
$cur_pr         = @fields[19];
$cur_dp         = @fields[20];
$cur_vis        = @fields[21];
$cur_hi         = @fields[23];
$cur_prec_today = @fields[25];
$cur_prec_1hr   = @fields[26];
}

$cur_sun_r = "@fields[34]:@fields[35]";
$cur_sun_s = "@fields[36]:@fields[37]";

# Use night icons between sunset and sunrise
$hour_sun_r = @fields[34];
$hour_sun_s = @fields[36];
if ($cur_hour > $hour_sun_s || $cur_hour < $hour_sun_r) {
  $cur_dayornight = "n";
} else {
  $cur_dayornight = "d";
}

open(F1,">$home/webfrontend/html/plugins/$psubfolder/webpage.html") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/webpage.html";
open(F,"<$home/templates/plugins/$psubfolder/$lang/themes/$theme.main.html") || die "Missing template <$home/templates/plugins/$psubfolder/$lang/themes/$theme.main.html";
while (<F>) {
  $_ =~ s/<!--\$(.*?)-->/${$1}/g;
  print F1 $_;
}
close(F);
close(F1);

#############################################
# MAP VIEW
#############################################

open(F1,">$home/webfrontend/html/plugins/$psubfolder/webpage.map.html") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/webpage.map.html";
open(F,"<$home/templates/plugins/$psubfolder/$lang/themes/$theme.map.html") || die "Missing template $home/templates/plugins/$psubfolder/$lang/themes/$theme.map.html";
  while (<F>) {
    $_ =~ s/<!--\$(.*?)-->/${$1}/g;
    print F1 $_;
  }
close(F);
close(F1);

#############################################
# Daily Forecast
#############################################

# Read data
open(F,"<$home/data/plugins/$psubfolder/dailyforecast.dat") || die "Cannot open $home/data/plugins/$psubfolder/dailyforecast.dat";
  our @dfcdata = <F>;
close(F);

foreach (@dfcdata){
  s/[\n\r]//g;
  my @fields = split(/\|/);

  my $per = @fields[0] - 1;

  ${dfc.$per._per} = @fields[0] - 1;
  ${dfc.$per._date} = @fields[1];
  ${dfc.$per._day} = @fields[2];
  ${dfc.$per._month} = @fields[3];
  ${dfc.$per._monthn} = @fields[4];
  ${dfc.$per._monthn_sh} = @fields[5];
  ${dfc.$per._year} = @fields[6];
  ${dfc.$per._hour} = @fields[7];
  ${dfc.$per._min} = @fields[8];
  ${dfc.$per._wday} = @fields[9];
  ${dfc.$per._wday_sh} = @fields[10];
  ${dfc.$per._pop} = @fields[13];
  ${dfc.$per._w_dirdes_h} = @fields[17];
  ${dfc.$per._w_dir_h} = @fields[18];
  ${dfc.$per._w_dirdes_a} = @fields[20];
  ${dfc.$per._w_dir_a} = @fields[21];
  ${dfc.$per._hu_a} = @fields[22];
  ${dfc.$per._hu_h} = @fields[23];
  ${dfc.$per._hu_l} = @fields[24];
  ${dfc.$per._we_icon} = @fields[25];
  ${dfc.$per._we_code} = @fields[26];
  ${dfc.$per._we_des} = @fields[27];
  if (!$metric) {
  ${dfc.$per._tt_h} = @fields[11]*1.8+32;
  ${dfc.$per._tt_l} = @fields[12]*1.8+32;
  ${dfc.$per._prec} = @fields[14]*0.0393700787;
  ${dfc.$per._snow} = @fields[15]*0.393700787;
  ${dfc.$per._w_sp_h} = @fields[16]*0.621;
  ${dfc.$per._w_sp_a} = @fields[19]*0.621;
  } else {
  ${dfc.$per._tt_h} = @fields[11];
  ${dfc.$per._tt_l} = @fields[12];
  ${dfc.$per._prec} = @fields[14];
  ${dfc.$per._snow} = @fields[15];
  ${dfc.$per._w_sp_h} = @fields[16];
  ${dfc.$per._w_sp_a} = @fields[19];
  }
  # Use night icons between sunset and sunrise
  #if (${dfc.$per._hour} > $hour_sun_s || ${dfc.$per._hour} < $hour_sun_r) {
  #  ${dfc.$per._dayornight} = "n";
  #} else {
  #  ${dfc.$per._dayornight} = "d";
  #}

}

open(F1,">$home/webfrontend/html/plugins/$psubfolder/webpage.dfc.html") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/webpage.dfc.html";
open(F,"<$home/templates/plugins/$psubfolder/$lang/themes/$theme.dfc.html") || die "Missing template <$home/templates/plugins/$psubfolder/$lang/themes/$theme.dfc.html";
  while (<F>) {
    $_ =~ s/<!--\$(.*?)-->/${$1}/g;
    print F1 $_;
  }
close(F);
close(F1);

#############################################
# Hourly Forecast
#############################################

# Read data
open(F,"<$home/data/plugins/$psubfolder/hourlyforecast.dat") || die "Cannot open $home/data/plugins/$psubfolder/hourlyforecast.dat";
  our @hfcdata = <F>;
close(F);

foreach (@hfcdata){
  s/[\n\r]//g;
  my @fields = split(/\|/);

  $per = @fields[0];

  ${hfc.$per._per} = @fields[0];
  ${hfc.$per._date} = @fields[1];
  ${hfc.$per._day} = @fields[2];
  ${hfc.$per._month} = @fields[3];
  ${hfc.$per._monthn} = @fields[4];
  ${hfc.$per._monthn_sh} = @fields[5];
  ${hfc.$per._year} = @fields[6];
  ${hfc.$per._hour} = @fields[7];
  ${hfc.$per._min} = @fields[8];
  ${hfc.$per._wday} = @fields[9];
  ${hfc.$per._wday_sh} = @fields[10];
  ${hfc.$per._hu} = @fields[14];
  ${hfc.$per._w_dirdes} = @fields[15];
  ${hfc.$per._w_dir} = @fields[16];
  ${hfc.$per._pr} = @fields[19];
  ${hfc.$per._dp} = @fields[20];
  ${hfc.$per._sky} = @fields[21];
  ${hfc.$per._sky._des} = @fields[22];
  ${hfc.$per._uvi} = @fields[23];
  ${hfc.$per._pop} = @fields[26];
  ${hfc.$per._we_code} = @fields[27];
  ${hfc.$per._we_icon} = @fields[28];
  ${hfc.$per._we_des} = @fields[29];
  if (!$metric) {
  ${hfc.$per._tt} = @fields[11]*1.8+32;
  ${hfc.$per._tt_fl} = @fields[12]*1.8+32;
  ${hfc.$per._hi} = @fields[13]*1.8+32;
  ${hfc.$per._w_sp} = @fields[17]*0.621;
  ${hfc.$per._w_ch} = @fields[18]*1.8+32;
  ${hfc.$per._prec} = @fields[24]*0.0393700787;
  ${hfc.$per._snow} = @fields[25]*0.393700787;
  } else {
  ${hfc.$per._tt} = @fields[11];
  ${hfc.$per._tt_fl} = @fields[12];
  ${hfc.$per._hi} = @fields[13];
  ${hfc.$per._w_sp} = @fields[17];
  ${hfc.$per._w_ch} = @fields[18];
  ${hfc.$per._prec} = @fields[24];
  ${hfc.$per._snow} = @fields[25];
  }
  # Use night icons between sunset and sunrise
  if (${hfc.$per._hour} > $hour_sun_s || ${hfc.$per._hour} < $hour_sun_r) {
    ${hfc.$per._dayornight} = "n";
  } else {
    ${hfc.$per._dayornight} = "d";
  }

}

open(F1,">$home/webfrontend/html/plugins/$psubfolder/webpage.hfc.html") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/webpage.hfc.html";
open(F,"<$home/templates/plugins/$psubfolder/$lang/themes/$theme.hfc.html") || die "Missing template <$home/templates/plugins/$psubfolder/$lang/themes/$theme.hfc.html";
  while (<F>) {
    $_ =~ s/<!--\$(.*?)-->/${$1}/g;
    print F1 $_;
  }
close(F);
close(F1);

$logmessage = "<OK> Webpages created successfully.\n";
&log;

#
# Create Cloud Weather Emu
#

# Original from Loxone Testserver: (ccord changed)
# http://weather.loxone.com:6066/forecast/?user=loxone_EEE000CC000F&coord=13.4,54.0768&format=1&asl=115
#        ^                  ^                          ^                  ^            ^        ^
#        URL                Port                       MS MAC             Coord        Format   Height
#
# The format could be 1 or 2, although Miniserver only seems to use format=1 
# (format=2 is xml-output, but with less weather data)
# The height is the geogr. height of your installation (seems to be used for windspeed etc.). You
# can give the heights in meter or set this to auto or left blank (=auto).

if ($emu) {

  $logmessage = "<INFO> Creating Files for Cloud Weather Emulator...\n";
  &log;

  #############################################
  # CURRENT CONDITIONS
  #############################################

  # Original file has 169 entrys, but always starts at 0:00 today or 12:00 yesterday. We alsways start with current data
  # (we don't have historical data) and offer 168 hourly forcast datasets. This seems to be ok for the miniserver.

  # Get current weather data from database

  open(F,"<$home/data/plugins/$psubfolder/current.dat") || die "Cannot open $home/data/plugins/$psubfolder/current.dat";
    $curdata = <F>;
  close(F);

  chomp $curdata;

  @fields = split(/\|/,$curdata);

  open(F,">$home/webfrontend/html/plugins/$psubfolder/emu/forecast/index.txt") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/emu/forecast/index.txt";
    print F "<mb_metadata>\n";
    print F "id;name;longitude;latitude;height (m.asl.);country;timezone;utc-timedifference;sunrise;sunset;\n";
    print F "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
    print F "</mb_metadata><valid_until>2030-12-31</valid_until>\n";
    print F "<station>\n";
    print F ";@fields[5];@fields[9];@fields[8];@fields[10];@fields[6];@fields[2];UTC" . substr (@fields[4], 0, 3) . "." . substr (@fields[4], 3, 2);
    print F ";@fields[34]:@fields[35];@fields[36]:@fields[37];\n"; 
    print F $epochdate->dmy('.') . ";";
    print F $epochdate->day_abbr() . ";";
    printf ( F "%02d",$epochdate->hour() );
    print F ";";
    printf ( F "%5.1f", @fields[11]);
    print F ";";
    printf ( F "%5.1f", @fields[12]);
    print F ";";
    printf ( F "%3d", @fields[16]);
    print F ";";
    printf ( F "%3d", @fields[15]);
    print F ";";
    printf ( F "%3d", @fields[17]);
    print F ";";
    print F "  0;  0;  0;";
    printf ( F "%5.1f", @fields[26]);
    print F ";";
    print F "  0;0.0;";
    printf ( F "%4d", @fields[19]);
    print F ";";
    printf ( F "%3d", @fields[13]);
    print F ";";
    print F "     0;";
    # Convert WU Weathercode to Lox Weathercode
    # WU: https://www.wunderground.com/weather/api/d/docs?d=resources/phrase-glossary 
    # Lox: https://www.loxone.com/dede/kb/weather-service/ seems not to be right (anymore),
    # correct Loxone Weather Types are:
    #  1 - wolkenlos
    #  2 - heiter 
    #  3 - heiter
    #  4 - heiter
    #  5 - heiter
    #  6 - heiter
    #  7 - wolkig
    #  8 - wolkig
    #  9 - wolkig
    # 10 - wolkig
    # 11 - wolkig
    # 12 - wolkig
    # 13 - wolkenlos
    # 14 - heiter
    # 15 - heiter
    # 16 - Nebel
    # 17 - Nebel
    # 18 - Nebel
    # 19 - stark bewölkt
    # 20 - stark bewölkt
    # 21 - stark bewölkt
    # 22 - bedeckt
    # 23 - Regen
    # 24 - Schneefall
    # 25 - starker Regen
    # 26 - starker Schneefall
    # 27 - kräftiges Gewitter
    # 28 - Gewitter
    # 29 - starker Schneeschauer
    # 30 - kräftiges Gewitter
    # 31 - leichter Regenschauer
    # 32 - leichter Schneeschauer
    # 33 - leichter Regen
    # 34 - leichter Schneeschauer
    # 35 - Schneeregen
    my $loxweathercode;
    #if (@fields[28] eq "16") {
    #  $loxweathercode = "21";
    #} elsif (@fields[28] eq "19") {
    #  $loxweathercode = "26";
    #} elsif (@fields[28] eq "12") {
    #  $loxweathercode = "10";
    #} elsif (@fields[28] eq "13") {
    #  $loxweathercode = "11";
    #} elsif (@fields[28] eq "14") {
    #  $loxweathercode = "18";
    #} elsif (@fields[28] eq "15") {
    #  $loxweathercode = "18";
    #} else {
    #  $loxweathercode = @fields[28];
    #}
    if (@fields[28] eq "2") {
      $loxweathercode = "7";
    } elsif (@fields[28] eq "3") {
      $loxweathercode = "8";
    } elsif (@fields[28] eq "4") {
      $loxweathercode = "9";
    } elsif (@fields[28] eq "5") {
      $loxweathercode = "10";
    } elsif (@fields[28] eq "6") {
      $loxweathercode = "16";
    } elsif (@fields[28] eq "7") {
      $loxweathercode = "7";
    } elsif (@fields[28] eq "8") {
      $loxweathercode = "7";
    } elsif (@fields[28] eq "9") {
      $loxweathercode = "26";
    } elsif (@fields[28] eq "10") {
      $loxweathercode = "33";
    } elsif (@fields[28] eq "11") {
      $loxweathercode = "33";
    } elsif (@fields[28] eq "12") {
      $loxweathercode = "23";
    } elsif (@fields[28] eq "13") {
      $loxweathercode = "23";
    } elsif (@fields[28] eq "14") {
      $loxweathercode = "28";
    } elsif (@fields[28] eq "15") {
      $loxweathercode = "28";
    } elsif (@fields[28] eq "16") {
      $loxweathercode = "26";
    } elsif (@fields[28] eq "18") {
      $loxweathercode = "32";
    } elsif (@fields[28] eq "19") {
      $loxweathercode = "33";
    } elsif (@fields[28] eq "20") {
      $loxweathercode = "24";
    } elsif (@fields[28] eq "21") {
      $loxweathercode = "24";
    } elsif (@fields[28] eq "22") {
      $loxweathercode = "24";
    } elsif (@fields[28] eq "23") {
      $loxweathercode = "24";
    } elsif (@fields[28] eq "24") {
      $loxweathercode = "24";
    } else {
      $loxweathercode = @fields[28];
    }
    printf ( F "%2d", $loxweathercode);
    print F ";";
    printf ( F "%4d", @fields[22]);
    print F ";\n";
  close(F);

  #############################################
  # HOURLY FORECAST
  #############################################

  # Get current weather data from database
  open(F,"<$home/data/plugins/$psubfolder/hourlyforecast.dat") || die "Cannot open $home/data/plugins/$psubfolder/hourlyforecast.dat";
    $hfcdata = <F>;
  close(F);

  # Original file has 169 entrys, but always starts at 0:00 today or 12:00 yesterday. We alsways start with current data
  # (we don't have historical data) and offer 168 hourly forcast datasets. This seems to be ok for the miniserver.

  $i = 0;
  my $hfcdate;

  open(F,">>$home/webfrontend/html/plugins/$psubfolder/emu/forecast/index.txt") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/emu/forecast/index.txt";

    foreach (@hfcdata) {

      if ( $i >= 168 ) { last; } # Stop after 168 datasets

      #chomp $_;

      @fields = split(/\|/,$_);

      $hfcdate = DateTime->new(
            year      => @fields[6],
            month     => @fields[3],
            day       => @fields[2],
            hour      => @fields[7],
            minute    => @fields[8],
      );

      # "local date;weekday;local time;temperature(C);feeledTemperature(C);windspeed(km/h);winddirection(degr);wind gust(km/h);low clouds(%);medium clouds(%);high clouds(%);precipitation(mm);probability of Precip(%);snowFraction;sea level pressure(hPa);relative humidity(%);CAPE;picto-code;radiation (W/m2);\n";
      print F $hfcdate->dmy('.') . ";";
      print F $hfcdate->day_abbr() . ";";
      printf ( F "%02d",$hfcdate->hour() );
      print F ";";
      printf ( F "%5.1f", @fields[11]);
      print F ";";
      printf ( F "%5.1f", @fields[12]);
      print F ";";
      printf ( F "%3d", @fields[17]);
      print F ";";
      printf ( F "%3d", @fields[16]);
      print F ";";
      printf ( F "%3d", @fields[17]);
      print F ";";
      printf ( F "%3d", @fields[21]);
      print F ";";
      printf ( F "%3d", @fields[21]);
      print F ";";
      printf ( F "%3d", @fields[21]);
      print F ";";
      printf ( F "%5.1f", @fields[24]);
      print F ";";
      printf ( F "%3d", @fields[26]);
      print F ";";
      print F "0.0;";
      printf ( F "%4d", @fields[19]);
      print F ";";
      printf ( F "%3d", @fields[14]);
      print F ";";
      print F "     0;";
      # Convert WU Weathercode to Lox Weathercode
      # WU: https://www.wunderground.com/weather/api/d/docs?d=resources/phrase-glossary 
      # Lox: https://www.loxone.com/dede/kb/weather-service/ seems not to be right (anymore),
      # correct Loxone Weather Types are:
      #  1 - wolkenlos
      #  2 - heiter 
      #  3 - heiter
      #  4 - heiter
      #  5 - heiter
      #  6 - heiter
      #  7 - wolkig
      #  8 - wolkig
      #  9 - wolkig
      # 10 - wolkig
      # 11 - wolkig
      # 12 - wolkig
      # 13 - wolkenlos
      # 14 - heiter
      # 15 - heiter
      # 16 - Nebel
      # 17 - Nebel
      # 18 - Nebel
      # 19 - stark bewölkt
      # 20 - stark bewölkt
      # 21 - stark bewölkt
      # 22 - bedeckt
      # 23 - Regen
      # 24 - Schneefall
      # 25 - starker Regen
      # 26 - starker Schneefall
      # 27 - kräftiges Gewitter
      # 28 - Gewitter
      # 29 - starker Schneeschauer
      # 30 - kräftiges Gewitter
      # 31 - leichter Regenschauer
      # 32 - leichter Schneeschauer
      # 33 - leichter Regen
      # 34 - leichter Schneeschauer
      # 35 - Schneeregen
      my $loxweathercode;
      #if (@fields[28] eq "16") {
      #  $loxweathercode = "21";
      #} elsif (@fields[28] eq "19") {
      #  $loxweathercode = "26";
      #} elsif (@fields[28] eq "12") {
      #  $loxweathercode = "10";
      #} elsif (@fields[28] eq "13") {
      #  $loxweathercode = "11";
      #} elsif (@fields[28] eq "14") {
      #  $loxweathercode = "18";
      #} elsif (@fields[28] eq "15") {
      #  $loxweathercode = "18";
      #} else {
      #  $loxweathercode = @fields[28];
      #}
      if (@fields[27] eq "2") {
        $loxweathercode = "7";
      } elsif (@fields[27] eq "3") {
        $loxweathercode = "8";
      } elsif (@fields[27] eq "4") {
        $loxweathercode = "9";
      } elsif (@fields[27] eq "5") {
        $loxweathercode = "10";
      } elsif (@fields[27] eq "6") {
        $loxweathercode = "16";
      } elsif (@fields[27] eq "7") {
        $loxweathercode = "7";
      } elsif (@fields[27] eq "8") {
        $loxweathercode = "7";
      } elsif (@fields[27] eq "9") {
        $loxweathercode = "26";
      } elsif (@fields[27] eq "10") {
        $loxweathercode = "33";
      } elsif (@fields[27] eq "11") {
        $loxweathercode = "33";
      } elsif (@fields[27] eq "12") {
        $loxweathercode = "23";
      } elsif (@fields[27] eq "13") {
        $loxweathercode = "23";
      } elsif (@fields[27] eq "14") {
        $loxweathercode = "28";
      } elsif (@fields[27] eq "15") {
        $loxweathercode = "28";
      } elsif (@fields[27] eq "16") {
        $loxweathercode = "26";
      } elsif (@fields[27] eq "18") {
        $loxweathercode = "32";
      } elsif (@fields[27] eq "19") {
        $loxweathercode = "33";
      } elsif (@fields[27] eq "20") {
        $loxweathercode = "24";
      } elsif (@fields[27] eq "21") {
        $loxweathercode = "24";
      } elsif (@fields[27] eq "22") {
        $loxweathercode = "24";
      } elsif (@fields[27] eq "23") {
        $loxweathercode = "24";
      } elsif (@fields[27] eq "24") {
        $loxweathercode = "24";
      } else {
        $loxweathercode = @fields[27];
      }
      printf ( F "%2d", $loxweathercode);
      print F ";   0;\n";

      $i++;

    }

    print F "</station>\n";

  close(F);

}

# Finish
exit;

#
# Subroutines
#

# error Message
sub error {
  $logmessage = "ERROR: $errormessage\n";
  print "\n$logmessage\n";
  exit;
}  

sub log {
  # Print
  if ($verbose || $error) {print $logmessage;}
  return();
}

sub send {

  # Create HTML webpage
  $logmessage = "<OK> Adding value to /plugins/$psubfolder/weatherdata.html. Value:$name\@$value\n";
  &log;
  open(F,">>$home/webfrontend/html/plugins/$psubfolder/weatherdata.html") || die "Cannot open $home/webfrontend/html/plugins/$psubfolder/weatherdata.html";
    print F "$name\@$value<br>\n";
  close(F);

  # Send by UDP
  if ($sendudp) {
   $tmpudp .= "$name\@$value; ";
   if ($udp == 1) {
    for ($i=1;$i<=$miniservers;$i++) {

      # Send value
      my $sock = IO::Socket::INET->new(
        Proto    => 'udp',
        PeerPort => $udpport,
        PeerAddr => ${miniserverip . "$i"},
      ) or die "<ERROR> Could not create socket: $!\n";
      $sock->send($tmpudp) or die "Send error: $!\n";
      if ($verbose) {
        $logmessage = "<OK> $sendqueue: Send OK to " . ${miniservername . "$i"} . ". IP:" . ${miniserverip . "$i"} . " Port:$udpport Value:$name\@$value\n";
        &log;
      }
      $sendqueue++;

    }
    $udp = 0;
    $tmpudp = "";
   }
  }

  return();

}

exit;
