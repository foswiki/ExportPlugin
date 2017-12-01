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

package Foswiki::Plugins::ExportPlugin::Exporter;

use strict;
use warnings;

use Foswiki ();
use Foswiki::Func ();
use Foswiki::Request ();
use Foswiki::Plugins ();
use Time::HiRes ();
use File::Spec();
use File::Copy();
use File::Path qw(make_path);
use Data::Dump qw(dump);

sub new {
  my $class = shift;

  my $this = bless({
    debug => $Foswiki::cfg{ExportPlugin}{Debug},
    exportDir => $Foswiki::cfg{ExportPlugin}{Dir},
    exportUrl => $Foswiki::cfg{ExportPlugin}{URL},
    baseUrl => $Foswiki::cfg{ExportPlugin}{BaseURL},
    @_
  }, $class);

  $this->{startTime} = $this->{lapseTime} = $this->getTime;
  $this->{urlOfAsset} = {};
  $this->{params} = {};

  $this->{assetsDir} = $this->{exportDir}.'/assets';
  $this->{assetsUrl} = $this->{exportUrl}.'/assets';

  $this->{htmlDir} = $this->{exportDir}.'/html';
  $this->{htmlUrl} = $this->{exportUrl}.'/html';

  $this->{baseUrl} ||= $this->{exportUrl};

  return $this;
}

sub params {
  my $this = shift;
  my $params = shift;

  if (defined $params) {
    $this->{params} = $params;
  }

  return $this->{params};
}

sub param {
  my ($this, $key) = @_;

  my $val = $this->{params}{$key};
  
  unless (defined $val) {
    my $request = Foswiki::Func::getRequestObject();
    $val = $request->param($key);
  }

  return $val;
}

sub writeDebug {
  my ($this, $msg) = @_;

  return unless $this->{debug};
  return unless $msg;

  $msg = dump($msg)."\n" if ref($msg);

  #Foswiki::Func::writeDebug(__PACKAGE__ . " - $msg");
  print STDERR __PACKAGE__ . " - $msg\n";
}

sub writeWarning {
  my ($this, $msg) = @_;

  #Foswiki::Func::writeWarning(__PACKAGE__ . " - $msg");
  print STDERR __PACKAGE__ . " - WARNING: $msg\n";
}

sub getTime {
  my $this = shift;

  return [Time::HiRes::gettimeofday];
}

sub getElapsedTime {
  my ($this, $since) = @_;

  my $startTime;
  my $endTime = $this->getTime();

  if ($since) {
    $startTime = $since;
  } else {
    $startTime = $this->{lapseTime};
    $this->{lapseTime} = $endTime;
  }

  return (Time::HiRes::tv_interval($startTime, $endTime) * 10000);
}

sub export {
  my ($this, $session, $subject, $verb, $response) = @_;

  my $debug = $this->param("debug");
  $this->{debug} = Foswiki::Func::isTrue($debug, 0) if defined $debug;

  $this->writeDebug("called export()");
  my $result = '';

  my $web = $this->param("web");
  my $topics = $this->param("topics") || $this->param("topic");
  my @topics = ();

  if (defined $web) {
    if (defined $topics) {
      @topics = split(/\s*,\s*/, $topics);
    } else {
      @topics = Foswiki::Func::getTopicList($web);
    }
    $result = $this->exportTopics($web, \@topics);
  } else {
    if (defined $topics) {
      $web = $session->{webName};
      @topics = split(/\s*,\s*/, $topics);
      $result = $this->exportTopics($web, \@topics);
    } else {
      my $webs = $this->param("webs");
      my @webs = ();
      my $include = $this->param("includeweb");
      my $exclude = $this->param("excludeweb");
      if (defined $webs) {
        @webs = split(/\s*,\s*/, $webs);
      } else {
        @webs = Foswiki::Func::getPublicWebList();
      }
      foreach my $web (sort @webs) {
        next if defined $include && $web !~ /$include/;
        next if defined $exclude && $web =~ /$exclude/;
        $web =~ s/\./\//g;
        $this->writeDebug("exporting $web");
        @topics = Foswiki::Func::getTopicList($web);
        $result = $this->exportTopics($web, \@topics);
      }
    }
  }


  #$this->writeDebug("exporting took ".$this->getElapsedTime($this->{startTime}));

  return $result;
}

sub exportTopics {
  my ($this, $web, $topics) = @_;

  my $include = $this->param("include");
  my $exclude = $this->param("exclude");
  my $forceUpdate = Foswiki::Func::isTrue($this->param("forceupdate"), 0);;

  @$topics = grep {/$include/} @$topics if defined $include;
  @$topics = grep {!/$exclude/} @$topics if defined $exclude;

  @$topics = grep {
    Foswiki::Func::topicExists($web, $_) ?  1: $this->writeWarning("woops, topic $web.$_ does not exist") && 0;
  } @$topics;

  my $i = 0;
  my $limit = $this->param("limit") || 0;
  if ($limit) {
    @$topics = splice(@$topics, 0, $limit);
  }

  my $len = scalar(@$topics);
  $this->writeDebug("exporting $len topic(s)");

  # capture main session running the rest handler
  my $mainSession = $Foswiki::Plugins::SESSION;

  foreach my $topic (@$topics) {
    $i++ ;
    my ($thisWeb, $thisTopic) = Foswiki::Func::normalizeWebTopicName($web ,$topic);

    my $src = $Foswiki::cfg{DataDir}.'/'.$thisWeb.'/'.$thisTopic.'.txt';
    my $dst = $this->getTargetPath($thisWeb, $thisTopic);

    unless ($forceUpdate) {
      my $mtimeSrc = (stat $src)[9] || 0;
      my $mtimeDst = (stat $dst)[9] || 0;

      if ($mtimeSrc < $mtimeDst) {
        $this->writeDebug("skipping $thisWeb.$thisTopic ... did not change");
        next;
      }
    }

    unless (Foswiki::Func::topicExists($thisWeb, $thisTopic)) {
      $this->writeWarning("$thisWeb.$thisTopic does not exist ... skipping");
      next;
    }

    # pushTopicContext does not suffice. we need a new Foswiki session for every topic
    # Foswiki::Func::pushTopicContext($thisWeb, $thisTopic);

    my $skin = $this->param("skin");
    my $cover = $this->param("cover");
    my $forceUpdate = $this->param("forceupdate") || 'off';
    my $request = Foswiki::Request->new();
    $request->param("topic", $thisWeb.'.'.$thisTopic);
    $request->param("skin", $skin);
    $request->param("cover", $cover);
    $request->param("forceupdate", $forceUpdate);

    my $wikiName = Foswiki::Func::getWikiName();
    my $session = Foswiki->new($wikiName, $request, {
      static => 1,
    });

    $Foswiki::Plugins::SESSION = $session;
 
    $this->writeDebug("$i/$len: exporting $thisWeb.$thisTopic to $dst");
    $this->exportTopic($thisWeb, $thisTopic);

    $session->finish();
    $Foswiki::Plugins::SESSION = $mainSession;

    last if $limit && $i > $limit;
  }

  # restore main session context;
  $Foswiki::Plugins::SESSION = $mainSession;

  return $this->postProcess($web, $topics);
}

sub postProcess {
  my ($this, $web, $topics) = @_;

  my $topic;
  if (defined $topics && @$topics) {
    $topic = shift @$topics;
  }
  return $this->getTargetUrl($web, $topic);
}

sub exportTopic {
  my ($this, $web, $topic) = @_;

  # not using a die() 
  $this->writeWarning("exportTopic not implemented");
}

sub getTargetPath {
  my ($this, $web, $topic) = @_;

  # not using a die() 
  $this->writeWarning("getTargetPath not implemented");
}

sub getTargetUrl {
  my ($this, $web, $topic) = @_;

  # not using a die() 
  $this->writeWarning("getTargetUrl not implemented");
}

sub extractExportableAreas {
  my ($this, $text) = @_;

  my $newText = '';
  my $seen = 0;
  my $inside = 1;
  foreach my $s (split(/(%(?:START|BEGIN)EXPORT%|%(?:STOP|END)EXPORT%)/, $text)) {
    if ($s =~ /^%(?:START|BEGIN)EXPORT%$/) {
      $newText = '' unless $seen;
      $inside = 1;
      $seen = 1;
    } elsif ($s =~ /^%(?:STOP|END)EXPORT%$/) {
      $inside = 0;
      $seen = 1;
    } else {
      $newText .= $s if $inside;
    }
  }

  return $newText;
}

sub readTemplate {
  my ($this, $web, $topic, $meta) = @_;

  my $skin = $this->param("skin");
  #$this->writeDebug("skin=".($skin||''));

  my $template;
  $template = Foswiki::Func::getPreferencesValue('VIEW_TEMPLATE');
  #$this->writeDebug("prefs template=".($template||''));
  #$template = $meta->getPreference("VIEW_TEMPLATE");
  #$this->writeDebug("topic template=".($template||''));

  if (!$template && $Foswiki::cfg{Plugins}{AutoTemplatePlugin}{Enabled}) {
    require Foswiki::Plugins::AutoTemplatePlugin;
    $template = Foswiki::Plugins::AutoTemplatePlugin::getTemplateName($web, $topic);
    #$this->writeDebug("auto template=".($template||''));
  }
  $template ||= "view";

  #$this->writeDebug("template=$template");

  my $result = Foswiki::Func::readTemplate($template, $skin);
  $result = Foswiki::Func::readTemplate("view", $skin) unless $result;

  return $result;
}

sub renderHTML {
  my ($this, $web, $topic, $meta, $text) = @_;

  my $session = $Foswiki::Plugins::SESSION;

  $text = $this->extractExportableAreas($text);
  #$this->writeDebug("text=$text");

  my $result = $this->readTemplate($web, $topic, $meta);
  $result =~ s/\%TEXT\%/$text/g;
  $result = $meta->expandMacros($result);
  $result = $meta->renderTML($result);

  if ($session->{cache}) {
    $session->{cache}->renderDirtyAreas(\$result);
  }

  if ($session->{plugins}) {
    $session->{plugins}->dispatch('completePageHandler', $result, '');
  }

  # do the zones
  $result = $this->renderZones($result);

  # cleanup stuff
  $result =~ s/<nop>//g;
  $result =~ s/<\/?noautolink>//g;
  $result =~ s/<!--[^\[<].*?-->//g;
  $result =~ s/^\s*$//gms;
  $result =~ s/<p><\/p>\s*([^<>]+?)\s*(?=<p><\/p>)/<p class='p'>$1<\/p>\n\n/gs;
  $result =~ s/\s*<\/p>(?:\s*<p><\/p>)*/<\/p>\n/gs;    # remove useless <p>s
  $result =~ s/\%\{(<pre[^>]*>)\}&#37;\s*/$1/g;
  $result =~ s/\s*&#37;\{(<\/pre>)\}\%/$1/g;

  # clean up unsatisfied WikiWords.
  $result =~ s/<([^\s]+)\s+[^>]*.+class=.foswikiNewLink.[^>]*>(.*?)<\/\1>/$2/g;

  my $pub = Foswiki::Func::getPubUrlPath();
  my $request = Foswiki::Func::getRequestObject();
  my $host = $session->{urlHost} || $request->header('Host') || 'localhost';
  my $viewUrl = $session->getScriptUrl(1, "view");
  my $viewUrlPath = $viewUrl;
  $viewUrlPath =~ s/^$host//g;

  #$this->writeDebug("host=$host, viewUrl=$viewUrl, viewUrlPath=$viewUrlPath");

  # Remove <base.../> tag
  $result =~ s/^<base[^>]+>.*?<\/base>.*$//im;
  $result =~ s/^base[^>]+\/>.*$//im;

  # remove non-macros and leftovers
  $result =~ s/%(?:REVISIONS|REVTITLE|REVARG|QUERYPARAMSTRING)%//g;
  $result =~ s/^%META:\w+{.*}%$//gm;

  # copy assets and rewrite urls
  $result =~ s!(['"\(])($Foswiki::cfg{DefaultUrlHost}|https?://$host)?$pub/(.*?)(\1|\))!$1.$this->copyAsset($3).$4!ge;

  # rewrite view links
  $result =~ s!href=(["'])(?:$viewUrl|$viewUrlPath)/($Foswiki::regex{webNameRegex}(?:\.|/)$Foswiki::regex{topicNameRegex})(\?.*?)?\1!'href='.$1.$this->{htmlUrl}.'/'.$2.'.html'.($3||'').$1!ge;

  # convert absolute to relative urls
  $result =~ s/$host//g;

  # fix anchors
  $result =~ s!href=(["'])\?.*?#!href=$1#!g;

  return $result;
}

sub copyAsset {
  my ($this, $assetName) = @_;

  $assetName =~ s/^\s+|\s+$//g;
  $assetName =~ s/\?.*$//;

  my $url = $this->{urlOfAsset}{$assetName};
  return $url if defined $url;

  my $path = "";
  my $file = $assetName;
  if ($assetName =~ /^(.*)\/(.*?)$/) {
    $path = $1;
    $file = $2;
  }

  my $newPath = $this->{assetsDir}.'/'.$path;
  my $src = Foswiki::Func::getPubDir().'/'.$assetName;
  my $dst = $newPath . '/' . $file;

  # collapse relative links
  while ($src =~ s/[^\/]+\/\.\.//g) {1;}
  while ($dst =~ s/[^\/]+\/\.\.//g) {1;}

  $url = $this->{assetsUrl}.'/'.$path.'/'.$file;
  
  if (-r $src) {

    unless (-d $newPath) {
      $this->writeDebug("... creating path $newPath");
      make_path($newPath);
    }

    $this->mirrorFile($src, $dst);
    #$this->mirrorFile($src.',v', $dst.',v');
    $this->mirrorFile($src.'.gz', $dst.'.gz') if $src =~ /\.(css|js)$/;

    $this->{urlOfAsset}{$assetName} = $url;
  } else {
    #$this->writeDebug("... src=$src, dst=$dst, url=$url");
    $this->writeWarning("$src is not readable");
  }

  # check css for additional resources, ie, url()
  if ($assetName =~ /\.css$/) {
    my %moreAssets = ();

    my $data = Foswiki::Func::readFile($src);
    #$this->writeDebug("... reading file $src");
    $data =~ s#\/\*.*?\*\/##gs;

    foreach my $asset (split(/;/, $data)) {
      next unless $asset =~ /url\(["']?(.*?)["']?\)/;
      $asset = $1;
      next if $asset =~ /^data:image/;
      $asset =~ s/\?.*$//;
      next if $moreAssets{$asset};
      #$this->writeDebug("... found more assets in $file: $asset");
      $moreAssets{$asset} = 1;
    }

    my $pub = Foswiki::Func::getPubUrlPath();
    foreach my $asset (keys %moreAssets) {

      unless ($asset =~ /^https?/) {

        if ($asset !~ m!^/!) {
          $asset = $path . '/' . $asset;
        } else {
          if ($asset =~ m!$pub/(.*)!) {
            my $old = $asset;
            $asset = $1;
          }
        }

        $this->copyAsset($asset);
      }
    }
  }

  return $url;
}

sub mirrorFile {
  my ($this, $src, $dst) = @_;

  return unless -e $src;

  my $forceUpdate = Foswiki::Func::isTrue($this->param("forceupdate"), 0);;

  my $mtimeSrc = (stat $src)[9];
  my $mtimeDst = (stat $dst)[9];

  if (!-e $dst || $forceUpdate || $mtimeSrc > $mtimeDst) {
    #$this->writeDebug("... copying file $src to $dst");
    File::Copy::copy($src, $dst) || $this->writeWarning("copying $src to $dst failed: $!");
  }
}

sub renderZones {
  my ($this, $text) = @_;

  # SMELL: call to unofficial api
  my $session = $Foswiki::Plugins::SESSION;
  if ($session->can("_renderZones")) { # old foswiki
    $text = $session->_renderZones($text);
  } else {
    $text = $session->zones()->_renderZones($text);
  }

  return $text;
}

1;
