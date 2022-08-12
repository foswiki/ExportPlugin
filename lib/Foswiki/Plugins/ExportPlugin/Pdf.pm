# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ExportPlugin is Copyright (C) 2017-2020 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::ExportPlugin::Pdf;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::ExportPlugin::Exporter ();
use File::Path qw(make_path);
use Error qw(:try);
use Digest::MD5 ();

our @ISA = qw( Foswiki::Plugins::ExportPlugin::Exporter );

sub new {
  my $class = shift;

  my $this = bless(
    $class->SUPER::new(
      @_
    ),
    $class
  );

  return $this;
}

sub exportTopic {
  my ($this, $web, $topic, $rev) = @_;

  $this->writeDebug("exportTopic($web,$topic)");

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic, $rev);

  my $wikiName = Foswiki::Func::getWikiName();
  my $cUID = Foswiki::Func::getCanonicalUserID();

  unless ($meta->haveAccess("VIEW", $cUID )) {
    $this->writeWarning("$wikiName has got no access to $web.$topic ... skipping");
    return 0;
  }

  # copy attachments
  my @attachments = $meta->find( 'FILEATTACHMENT' );
  foreach my $attachment (@attachments) {
    $this->copyAsset("$web/$topic/$attachment->{name}");
  }

  # generate output format
  my $result = $this->renderHTML($web, $topic, $meta, $text);

  # rewrite some urls to use file://..
  $result =~ s/(<link[^>]+href=["'])([^"']+)(["'])/$1.$this->toFileUrl($2).$3/ge;
  $result =~ s/(<img[^>]+src=["'])([^"']+)(["'])/$1.$this->toFileUrl($2).$3/ge;

  #$this->writeDebug($result);
  my $path = $this->{htmlDir}.'/'.$web;
  my $file = $path.'/'.$topic.'.html';
  my $url = $this->{htmlUrl}.'/'.$web.'/'.$topic.'.html';

  $this->writeDebug("file=$file, url=$url");

  make_path($path);
  Foswiki::Func::saveFile($file, $result, 1);

  my $pdfFile = $this->convertToPdf($web, $topic, $rev, $file);

  #$this->writeDebug("... took ".$this->getElapsedTime."ms");

  return $pdfFile;
}

sub convertToPdf {
  my ($this, $web, $topic, $rev, $htmlFile) = @_;

  my ($path, $pdfFile) = $this->getTargetPath($web, $topic, $rev);

  File::Path::mkpath($path);

  # create print command
  my $baseUrl = $this->{baseUrl};

  my $cmd = $Foswiki::cfg{ExportPlugin}{PdfCmd} 
    || $Foswiki::cfg{GenPDFWeasyPlugin}{WeasyCmd}
    || '/usr/local/bin/weasyprint --base-url %BASEURL|U% --media-type print --encoding utf-8 %INFILE|F% %OUTFILE|F%';

  $this->writeDebug("cmd=$cmd");
  $this->writeDebug("BASEURL=$baseUrl");
  $this->writeDebug("htmlFile=" . $htmlFile);
  $this->writeDebug("pdfFile=$pdfFile");

  # execute
  my ($output, $exit, $error) = Foswiki::Sandbox->sysCommand(
    $cmd,
    BASEURL => $baseUrl,
    OUTFILE => $pdfFile,
    INFILE => $htmlFile,
  );

  #$this->writeDebug("output=$output");
  #$this->writeDebug("exit=$exit");
  $this->writeDebug("error=$error");

  if ($exit) {
    throw Error::Simple("execution of weasy failed ($exit) \n\n$error");
  }

  return $pdfFile;
}

sub getTargetPath {
  my ($this, $web, $topic, $rev, $name) = @_;

  my $path = $this->{assetsDir}.'/';
  $path .= $web if defined $web;
  $path .= '/'.$topic if defined $topic;

  my $file = 'genpdf_'.($name||$topic||$web).($rev?"_$rev":"").'.pdf';

  $file =~ s{[\\/]+$}{};
  $file =~ s!^.*[\\/]!!;
  $file =~ s/$Foswiki::regex{filenameInvalidCharRegex}//g;
  $file = $path.'/'.$file;

  return wantarray ? ($path, $file) : $file;
}

sub getTargetUrl {
  my ($this, $web, $topic, $rev, $name) = @_;

  if (ref($topic)) {
    $topic = shift @$topic; # SMELL
    ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
  }

  my $path = $this->{assetsUrl}.'/'.$web;
  $path .= '/'.$topic if defined $topic;

  my $file = 'genpdf_'.($name||$topic||$web).($rev?"_$rev":"").'.pdf';

  $file =~ s{[\\/]+$}{};
  $file =~ s!^.*[\\/]!!;
  $file =~ s/$Foswiki::regex{filenameInvalidCharRegex}//g;
  $file = $path.'/'.$file."?t=".time();

  return $file;
}

sub postProcess {
  my ($this) = @_;

  if (Foswiki::Func::isTrue($this->param("join"), 0) && scalar(@{$this->publishSet()}) > 1) {

    my @files = ();
    my $md5 = Digest::MD5->new();
    my $web;

    foreach my $item (@{$this->publishSet()}) {
      $this->writeDebug("...joining $item->{web}.$item->{topic}".($item->{rev}?"rev=$item->{rev}":""));
      $web ||= $item->{web};

      my $filePath = $this->getTargetPath($item->{web}, $item->{topic}, $item->{rev});
      push @files, $filePath;
      $md5->add($filePath);
    }

    $md5 = $md5->hexdigest;
    my $pdfFile = $this->getTargetPath($web, undef, undef, $md5);

    $this->writeDebug("pdfFile=$pdfFile");

    my $cmd = $Foswiki::cfg{ExportPlugin}{PdfJamCmd} 
      || '/usr/bin/pdfjam --quiet --fitpaper true --rotateoversize true --suffix joined --outfile %OUTFILE|F% %FILES|F%';

    # execute
    my ($output, $exit, $error) = Foswiki::Sandbox->sysCommand(
      $cmd,
      OUTFILE => $pdfFile,
      FILES => \@files
    );

    #$this->writeDebug("output=$output");
    #$this->writeDebug("exit=$exit");
    #$this->writeDebug("error=$error");

    if ($exit) {
      throw Error::Simple("execution of pdfjam failed ($exit) \n\n$error");
    }

    return $this->getTargetUrl($web, undef, undef, $md5);
  } 

  
  # SMELL: why can't we use $this->SUPER::postProcess();
  my $item = @{$this->publishSet()}[0];
  return $this->getTargetUrl($item->{web}, $item->{topic}, $item->{rev});
}

1;

