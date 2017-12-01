# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ExportPlugin is Copyright (C) 2017 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::ExportPlugin::Html;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::ExportPlugin::Exporter ();
use File::Path qw(make_path);
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
  my ($this, $web, $topic) = @_;

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $wikiName = Foswiki::Func::getWikiName();
  my $cUID = Foswiki::Func::getCanonicalUserID();

  unless ($meta->haveAccess("VIEW", $cUID )) {
    $this->writeWarning("$wikiName has got no access to $web.$topic ... skipping");
    return;
  }

  # copy attachments
  my @attachments = $meta->find( 'FILEATTACHMENT' );
  foreach my $attachment (@attachments) {
    $this->copyAsset("$web/$topic/$attachment->{name}");
  }

  # generate output format
  my $result = $this->renderHTML($web, $topic, $meta, $text);

  #$this->writeDebug($result);
  my ($path, $file) = $this->getTargetPath($web, $topic);
  my $url = $this->getTargetUrl($web, $topic);

  #$this->writeDebug("file=$file, url=$url");

  make_path($path);
  Foswiki::Func::saveFile($file, $result, 1);

  #$this->writeDebug("... took ".$this->getElapsedTime."ms");
}

sub getTargetPath {
  my ($this, $web, $topic) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic || $Foswiki::cfg{HomeTopicName});

  my $path = $this->{htmlDir}.'/'.$web;
  my $file = $path.'/'.$topic.'.html';

  return wantarray ? ($path, $file) : $file;
}

sub getTargetUrl {
  my ($this, $web, $topic) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic || $Foswiki::cfg{HomeTopicName});

  return $this->{htmlUrl}.'/'.$web.'/'.$topic.'.html';
}

1;
