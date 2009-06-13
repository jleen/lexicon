#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Color::Scheme;
use HTML::Form;
use HTTP::Cookies;
use LWP;
use Storable;
use Time::HiRes qw( usleep );
use URI;

$Data::Dumper::Sortkeys = 1;

my $alts    = {}; # key = wikiname, value = hash { key = display name, val=1 }
my $authors = {}; # key = wikiname, value = author full name
my $canonNm = {}; # key = wikiname, value = canonical display name
my $links   = {}; # key = wikiname, value = hash { key = wikilink, val=count }
my $refs    = {}; # val = hash { key = author referencing article, val=count }
my $revauth = {}; # key = author, value = array [ list of articles by author ]

# These are known documents which have no author, and are used as the
# start page for crawling the wiki
my @kIndexDocs = qw( Index ByAuthor Timeline Welcome );

for (@kIndexDocs)
{
  $authors->{$_}  = '';
}

# Return a list of all known articles (filter out non-article documents)
sub all()
{
  # Non-article documents include the list Index, ByAuthor, etc, as well
  # as all author names (in both short (CamelCase) and long forms
  my $idx = { map { $_ => 1 } @kIndexDocs, keys %$revauth };
  map { my $a = $_; $a =~ s/ //g; $idx->{$a} = 1 } keys %$revauth;
  map { my $a = $_; $a =~ s/ /_/g; $idx->{$a} = 1 } keys %$revauth;

  my @all = grep { !exists $idx->{$_} } keys %$links;
  return @all;
}

# Return working directory for storing all temp and generated files
sub viridiaDir()
{
  return $ENV{'HOME'} . "/viridia/";
}

# File name for storing content of a given article
sub fileContent($)
{
  my ($article) = @_;
  $article =~ s/ /_/g;
  return viridiaDir() . "content/" . $article;
}

sub viridiaUrl($)
{
  return URI->new("http://www.saturnvalley.org/viridia/".$_[0]);
}

{
  my $cookiefile = viridiaDir() . "cookies.txt";
  my $agent      = '"Mozilla/5.0 (compatible; Konqueror/3.2; Linux)"';

  my $cookie_jar = HTTP::Cookies->new('file'     => $cookiefile,
                                      'autosave' => 1,);

  my $hasCookie = 0;

  sub _cookie_callback
  {
    my ($version,$key,$val,$path,$domain,$port,
        $path_spec,$secure,$expires,$discard,$hash) = @_;

    if (($key eq "MOIN_SESSION") &&
        ($path eq "/viridia") &&
        ($domain eq "www.saturnvalley.org"))
    {
      $hasCookie = 1;
    }
    return;
  }

  sub hasViridiaCookie()
  {
    return 1 if ($hasCookie);
    $cookie_jar->scan(\&_cookie_callback);
    return $hasCookie;
  }

  sub browser()
  {
    my $browser = LWP::UserAgent->new();
    $browser->cookie_jar($cookie_jar);
    $browser->env_proxy(); # Load proxy settings from environment
    $browser->agent($agent);

    return $browser;
  }
}

# authenticates to wiki, obtaining appropriate cookie for future use
sub login($$)
{
  my ($user, $pass) = @_;

  my $form;
  {
    my $url = viridiaUrl("Index?action=login");

    my $browser = browser();
    my $request = HTTP::Request->new("GET");
    # Send the request and get a response back from the server
    $request->url($url);
    my $response = $browser->request($request);
    my @forms = HTML::Form->parse($response);
    ($form) = grep { $_->attr("name") && $_->attr("name") eq "loginform" }
      @forms;
  }

  $form->find_input('name')->value($user);
  $form->find_input('password')->value($pass);
  my $request = $form->click();

  my $browser = browser();
  my $response = $browser->request($request);

  return $response->is_success() &&
    $response->content() !~ m/Invalid username or password/;
}

# get($article) fetch a document from the wiki, memoize method by
# storing on disk and in memory
{
  my $content = {};
  sub get($);

  sub get($)
  {
    my ($article) = @_;
    $article =~ s/ /_/g;

    return '' if ($article eq "Welcome");

    return $content->{$article} if (exists $content->{$article});

    my $file = fileContent($article);
    if (-r $file && ($article ne "Index")) # never read Index from disk
    {
      open FILE, $file;
      $content->{$article} = join("", <FILE>);
      close FILE;

      return $content->{$article};
    }

    print "Fetching $article\n";

    my $url = viridiaUrl($article . "?action=raw");

    my $browser = browser();
    my $request = HTTP::Request->new("GET");
    # Send the request and get a response back from the server
    $request->url($url);
    my $response = $browser->request($request);
    my $result = $response->content();

    if ($response->is_success())
    {
      $result =~ s/\r\n/\n/g;    # dos2unix

      open FILE, ">" . $file;
      print FILE $result;
      close FILE;

      $content->{$article} = $result;

      return $result;
    }

    if ((503 == $response->code()) &&
        ($result =~ m/You triggered the wiki's surge protection/))
    {
      my $sleeptime = 41;
      print STDERR $result;
      print STDERR
        "\n\n>>>Sleeping for $sleeptime seconds, then retrying\n";
      sleep $sleeptime;
      return get($article);
    }

    $content->{$article} = '';
    open FILE, ">" . $file;
    close FILE;

    return '';
  }
}

# For a given article name, fetch document, parse and return list of
# links; update list of alternate display names for each linked document
# as a side-effect
sub getLinks($)
{
  my ($article) = @_;
  return keys %{ $links->{$article} } if (exists $links->{$article});
  $links->{$article} = {};

  my $res = get($article);

  my @l = $res =~ m/\[\[(.*?)\]\]/g;
  grep { s/_/ /g } @l;

  {
    my @alts = grep { m/\|/ } @l;
    foreach (@alts)
    {
      my ($real, $alt) = split /\|/;
      $real = ucfirst $real;
      $alt  = ucfirst $alt;
      if ((uc $real ne uc $alt) &&
          ((uc $real) . "'S" ne uc $alt))
      {
        $alts->{$real}->{$alt} = 1;
      }
    }
  }

  grep { s/\|.*// } @l;

  foreach (@l)
  {
    $links->{$article}->{$_} ||= 0;
    $links->{$article}->{$_}++;
  }

  return @l;
}

# For a given article, parse content and determine author
sub getAuthor($)
{
  my ($article) = @_;

  return $authors->{$article} if (exists $authors->{$article});
  my $res = get($article);
  my @art = split(/[\r\n]/, $res);
  @art = grep { !m/^\s*$/ } @art;
  my $auth = '';

  if (0 < scalar @art)
  {
    $auth = pop @art;

    $auth =~ s/Thucidides Plutonium/Thucydides Plutonium/;

    $auth =~ s/^For your benefit.\s*//i;    # common sig of MK
    $auth =~ s/is gathering its notes on this subject\.//i; # WIP of R3
    $auth =~ s/apologizes for the length.*//;
    $auth =~ s/is preparing.*//;
    $auth =~ s/has returned.*//;
    $auth =~ s/doesn't need to do.*//;
    $auth =~ s/LanceM/Lance M/;

    $auth =~ s/'//g;                        # remove italics and bolding
    $auth =~ s/^-*//;
    $auth =~ s/^\s*//;
    $auth =~ s/-*$//;
    $auth =~ s/\[\[(.*)\]\]/$1/;            # some sigs are wikilinks
    $auth =~ s/.*\|//;
    $auth =~ s/^\s+//;
    $auth =~ s/\s+$//;

    return '' if ($auth =~ m/^Page .* not found.$/);
    $authors->{$article} = $auth;
  }

  return $auth;
}

# For a given author, return their initials.  Handle a few special cases.
{
  my $intls = {};
  $intls->{'Col. Marthius Tholosar'} = 'ColMT';
  $intls->{'Thucydides Plutonium'}   = 'ThP';

  sub initials($)
  {
    my ($auth) = @_;
    return $intls->{$auth} if (exists $intls->{$auth});
    my $a = $auth;
    $auth =~ s/-/ / if ($auth !~ m/ /);
    $auth = join('', map { m/^(.)/ } split(/ /, $auth));
    $intls->{$a} = $auth;
    return $auth;
  }
}

# For each author, return a unique color (to be used when generating graph
# of articles)
{
  my $colors = {};
  my $i      = 0;
  my $scheme = Color::Scheme->new()->scheme("triade")->variation("pastel");

  #  my $scheme = Color::Scheme->new()->scheme("tetrade");
  my @list = $scheme->colors();

  sub authColor($)
  {
    my ($auth) = @_;
    return $colors->{$auth} if (exists $colors->{$auth});
    my $c = "#" . $list[$i];
    $colors->{$auth} = $c;
    print "Color $i is $c for $auth\n";
    $i++;
    return $c;
  }
}

sub getUserPass()
{
  print "Enter username for Viridia: ";
  my $user = <STDIN>;
  chomp($user);
  return (undef, undef) unless length $user;

  print "Password: ";
  system("stty -echo");
  my $password = <STDIN>;
  system("stty echo");
  print "\n";    # because we disabled echo
  chomp($password);
  return ($user, $password);
}

# Initialize everything -- start with Index page, and crawl whole wiki,
# extracting information as we go
sub init()
{
  if (! -d viridiaDir())
  {
    mkdir viridiaDir();
  }
  if (! -d fileContent(""))
  {
    mkdir fileContent("");
  }

  if (! hasViridiaCookie())
  {
    my ($user,$pass) = getUserPass();
    if (! login($user, $pass) )
    {
      print "Invalid username/password; you will not be able to upload\n";
    }
  }

  # We want to make sure we always fetch these two files, so remove our
  # local copy (if any)
  unlink(fileContent("ByAuthor"));
  unlink(fileContent("Index"));
  # Start with the Index page, and build up all page links
  for (@kIndexDocs)
  {
    for (getLinks($_))
    {
      getLinks($_);
    }
  }

  my @all;
  {
    @all = keys %$links;
    my @m = @all;
    foreach (@all)
    {
      push @m, keys %{ $links->{$_} };
    }

    my %h = map { $_ => 1 } @m;
    @all = sort keys %h;
  }

  # ensure we have links and authors for all pages
  foreach (@all)
  {
    getLinks($_);
    getAuthor($_);
  }

  # sort our list of authors (article -> author)
  foreach my $art (keys %$authors)
  {
    my $auth = getAuthor($art);
    push @{ $revauth->{$auth} }, $art if ($auth);
  }

  # build a reverse author list (author -> articles)
  foreach (keys %$revauth)
  {
    $revauth->{$_} = [sort @{ $revauth->{$_} }];
  }

  # build a canonical list of "full" article names
  foreach (@all)
  {
    my @cands = ($_, keys %{ $alts->{$_} });
    @cands = sort { length $b <=> length $a } @cands;
    $canonNm->{$_} = $cands[0];
  }

  # These are a few articles where the above heuristic is incorrect
  for my $art (('Achronic Inverter',
                'Almnetic Decay',
                'Arcological Mania',
                'Arcturianism',
                'Astrogation',
                'Byforalla',
                'Core Process',
                'Crilinka',
                'Ctjn Empire',
                'Darkness Ascending',
                'Dries Historical Catalog',
                'Druniad',
                'Dust Men',
                'Endotian Calendar',
                'Erasermind',
                'First Explorers',
                'Flarebird',
                'Garott Ornati',
                'Hegemonic Purge',
                'Hermes Cluster',
                'Illbreed',
                'Intoa',
                'Juvi Juice',
                'Knosis',
                'Kriegball',
                'Lanian Tribes',
                'Logomerology',
                'No-Nothing',
                'Orsinder',
                'Parallax Urgency',
                'Starlight Documents',
                'Tiari',
                'Tomorrow Hive',
                'Viridia Prime',
                'Xenomathematics'))
  {
    $canonNm->{$art} = $art;
  }
  $canonNm->{'Captain Logomere'} = 'Logomere, Captain Joseph';
  $canonNm->{'Dagmar Yvensk'} = 'Yvensk, Dagmar';
  $canonNm->{'Dula Jyrexil'} = 'Jyrexil, Dula';
  $canonNm->{'Emmanuel Grippe'} = 'Grippe, Emmanuel';
  $canonNm->{'Istvex'} = 'Istvex, Nia-Ume and Kyril';
  $canonNm->{'First Nova Generator'} = 'Nova Generator, First';
  $canonNm->{'Second Nova Generator'} = 'Nova Generator, Second';
  $canonNm->{'Third Nova Generator'} = 'Nova Generator, Third';

  # build list of references (by author)
  foreach my $art (@all)
  {
    my $auth = getAuthor($art);
    if ($auth)
    {
      foreach my $link (keys %{ $links->{$art} })
      {
        $refs->{$link} = {} if (!exists $refs->{$link});
        $refs->{$link}->{$auth} ||= 0;
        $refs->{$link}->{$auth}++;
      }
    }
  }
}

# Generate a link to an article, using the canonical display name
sub articleLink($)
{
  my ($article) = @_;

  my $can = $canonNm->{$article};
  if ($can ne $article)
  {
    return "[[$article|$can]]";
  }

  return "[[$article]]";
}

# Generate a list of all authors who reference a given article
sub refString($)
{
  my ($art) = @_;
  my $ret = '';

  if (scalar keys %{ $refs->{$art} })
  {
#    $ret .= "ref-".scalar keys %{$refs->{$art}};
    $ret .= "ref";
    $ret .= " ";
    $ret .= join(", ", map { initials($_) } sort keys %{ $refs->{$_} });
    $ret .= "";
  }

  return $ret;
}

# Build the "ByAuthor" page, which lists all authors in order and the
# articles written by each author
sub buildByAuthor()
{
  print "Building \"ByAuthor\"\n";

  open FILE, ">" . viridiaDir() . "ByAuthor";
  print FILE "= Index By Author =\n\n";
  foreach my $auth (sort keys %$revauth)
  {
    my @arts = @{ $revauth->{$auth} };
    @arts = sort { $canonNm->{$a} cmp $canonNm->{$b} } @arts;

    my $total = 0;
    for (@arts)
    {
      $total += scalar keys %{ $refs->{$_} };
    }
    $total = scalar @arts;

    print FILE "=== $auth (", initials($auth), ") (", $total, ") ===\n";

    for (@arts)
    {
#      print FILE " 1. ";
      print FILE " * ";
      print FILE articleLink($_);
      print FILE " (", refString($_), ")" if (refString($_));
      print FILE "\n";
    }
    print FILE "\n";
  }
  close FILE;
}

# Build "Index" page, which lists all articles, and the author for each
sub buildIndex()
{
  print "Building \"Index\"\n";

  open FILE, ">" . viridiaDir() . "Index";
  print FILE
    "= Index =\n\n",
    "Alphabetical index of all entries in the Viridian Lexicon.  ",
    "See also [[Timeline]] for a chronological listing of major events, ",
    "or view pages [[ByAuthor|by author]].\n";

  my @all = all();

  for my $fl ('A' .. 'Z')
  {
    my @arts = grep { $canonNm->{$_} =~ m/^$fl/ } @all;
    @arts = sort { $canonNm->{$a} cmp $canonNm->{$b} } @arts;

    print FILE "\n== $fl (", scalar @arts, ") ==\n";
    for (@arts)
    {
      print FILE " * ", articleLink($_), " (";
      my $auth = getAuthor($_);
      print FILE "by ", initials($auth) if ($auth);
      print FILE "; " if ($auth && refString($_));
      print FILE refString($_), ")\n";
    }
  }

  close FILE;
}

# Build a graph (using graphviz) of all articles and how they link
# together
sub buildGraph()
{
  print "Building Graph\n";

  my @all = all();

  open FILE, ">" . viridiaDir() . "viridia.dot";
  print FILE "digraph viridia\n{\n";

  # existing articles all get one formatting, including a color indicating
  # the author
  for my $art (grep { getAuthor($_) } @all)
  {
    print FILE "\"$art\" [label=\"$art\\n", getAuthor($art), "\"",
      " color=\"", authColor(getAuthor($art)), "\" ",
      "style=\"rounded,filled\" shape=\"box\"]\n";
  }
  print FILE "\n";

  # non-existing articles get a different formatting
  print FILE "  node [color=\"black\"]\n";
  for my $art (grep { !getAuthor($_) } @all)
  {
    print FILE "\"$art\" [label=\"$art\"]\n";
  }
  print FILE "\n";

  # Now fill in all links as edges
  for my $art (@all)
  {
    for my $link (getLinks($art))
    {
      print FILE "\"$art\" -> \"$link\"\n";
    }
  }
  print FILE "}\n";
  close FILE;

  # Use "dot" (part of graphviz) to generate png
  system("dot -Tpng " . viridiaDir() . "viridia.dot -o " . viridiaDir() .
         "viridia.png");
  open FILE, ">" . viridiaDir() . "viridia.html";
  print FILE "<img border=\"0\" src=\"viridia.png\" usemap=\"#lexicon\">\n";
  close FILE;
  system("dot -Tcmapx " . viridiaDir() . "viridia.dot >> " . viridiaDir() .
         "viridia.html");
}

sub updateFile($)
{
  my ($file) = @_;
  return 0  if (! -r viridiaDir() . $file);

  print "Updating \"$file\"\n";

  open FILE, "<" . viridiaDir() . $file;
  my $content = join("", <FILE>);
  close FILE;

  my $form;
  {
    my $url = viridiaUrl($file . "?action=edit&editor=text");
    my $browser = browser();
    my $request = HTTP::Request->new("GET");
    # Send the request and get a response back from the server
    $request->url($url);
    my $response = $browser->request($request);
    my @forms = HTML::Form->parse($response);
    ($form) = grep { $_->attr("id") && $_->attr("id") eq "editor" }
      @forms;
  }

  $form->find_input('savetext')->value($content);
  $form->find_input('comment')->value("updated by viridia-validate.pl");
  my $request = $form->click('button_save');

  my $browser = browser();
  my $response = $browser->request($request);

  return $response->is_success();
}


init();

buildByAuthor();
buildIndex();
buildGraph();

if (grep { $_ eq "-u" } @ARGV)
{
  if (hasViridiaCookie())
  {
    updateFile("ByAuthor");
    updateFile("Index");
    # Since we've now updated the file on the wiki, remove our (now
    # out-of-date) local copy
    unlink(fileContent("ByAuthor"));
    unlink(fileContent("Index"));
  }
  else
  {
    print "Not updating wiki, due to lack of authentication cookie\n";
  }
}
