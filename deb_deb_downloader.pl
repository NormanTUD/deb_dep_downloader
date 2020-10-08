#!/usr/bin/perl

use strict;
use warnings;
use autodie;
use LWP::Simple;
use Data::Dumper;
use Term::ANSIColor;
use Digest::MD5 qw/md5_hex/;
use Memoize;

memoize 'download_dependency';

my @valid_arch = qw/alpha amd64 arm64 armel armhf hppa i386 m68k mips64el mipsel ppc64 ppc64el riscv64 s390x sh4 sparc64 x32/;
my $valid_arches_str = join(', ', @valid_arch);

my %options = (
        debug => 0,
        package => undef,
        version => undef,
        outdir => undef,
        arch => undef,
        download_suggested => 0,
        download_recommended => 0,
        max_depth => 10,
        dryrun => 0,
        mirror_country => 'de'
);

sub warn_red (@) {
        foreach (@_) {
                warn color("red").$_.color("reset")."\n";
        }
}

sub debug (@) {
        return unless $options{debug};
        foreach (@_) {
                warn color("on_blue").$_.color("reset")."\n";
        }
}

analyze_args(@ARGV);

main();

sub main {
        debug "main";
        my @dependency_names = get_dependency_names();
        push @dependency_names, $options{package};

        foreach my $name (@dependency_names) {
                download_dependency($name, $options{arch});
        }
}

sub download_virtual_dependency {
        my $name = shift;
        debug "download_virtual_dependency($name)";

        my $found_links = 0;
        my $url = "https://packages.debian.org/de/$options{version}/$name";

        my $site = myget($url);

        while ($site =~ m#<dt><a href="/de/sid/([^"]+)">[^<]+</a></dt>#gism) {
                my $name = $1;
                download_dependency($name, $options{arch}, 1);
                my @dependency_names = get_dependency_names($name);
                foreach my $this_name (@dependency_names) {
                        download_dependency($this_name, $options{arch}, 1);
                }
                $found_links++;
        }

        return $found_links;
}

sub download_dependency {
        my $name = shift;
        my $arch = shift;
        my $tried_virtual = shift // 0;
        debug "download_dependency($name, $arch, $tried_virtual)";

        my $url = "https://packages.debian.org/de/$options{version}/$arch/$name/download";
        my $site = myget($url);
        my $dl_url = undef;
        my $found_links = 0;
        if(defined $site && $site =~ m#<a href="(http://ftp\.$options{mirror_country}\.debian\.org/debian/[^"]+.deb)">ftp\.$options{mirror_country}\.debian\.org/debian</a></li>#) {
                $dl_url = $1;
        } elsif(!$tried_virtual && defined $site && $site =~ m#passendes paket gefunden#i) {
                $found_links = download_virtual_dependency($name);
        } elsif($arch ne 'all') {
                warn "Did not find any links for $name for the architecture $arch ($url), trying 'all'";
                return download_dependency($name, 'all', $tried_virtual);
        } else {
                warn_red "Could not find any source for $name for either $options{arch} or 'all'";
                return undef;
        }

        if(!$found_links) {
                if(defined($dl_url)) {
                        my $filename = $dl_url;
                        $filename =~ s#.*/##g;
                        my $file_path = "$options{outdir}/$filename";
                        if(!-e $file_path) {
                                my $command = "wget $dl_url -O $file_path";
                                debug $command;
                                if($options{dryrun}) {
                                        debug "Enabled dryrun. Not really downloading new stuff";
                                } else {
                                        system($command);
                                        if($?) {
                                                die "ERROR $?";
                                        } else {
                                                warn "OK: successfully downloaded $name for $arch\n";
                                        }
                                }
                        } else {
                                warn "File $filename already exists in $file_path\n";
                        }
                } else {
                        warn_red "Could not find download for $name ($arch)";
                }
        }
}

sub get_dependency_names {
        my $package = shift // $options{package};
        my $depth = shift // 0;
        if($depth >= $options{max_depth}) {
                return +();
        }
        debug "get_dependency_names($package)";
        my $url = "https://packages.debian.org/de/$options{version}/$package";
        my $html = myget($url);

        my @types = qw/dep/;

        push @types, 'sug' if $options{download_suggested};
        push @types, 'rec' if $options{download_recommended};

        my $types_str = '(?:'.join('|', @types).')';

        my @names = ();

        while ($html =~ m#<dt><span class="nonvisual">$types_str:</span>[\r\n\s]*<a href="/de/$options{version}/([^"]+)">#gi) {
                push @names, $1;
                push @names, get_dependency_names($1, ++$depth);
        }

        return @names;
}

sub _help {
        my $exit = shift // 0;


        my $str = <<EOF;
Downloads Debian-dependencies from the website packages.debian.org
--debug                         Enables Debug-output
--package=name                  Sets the package name
--version=version               Sets the debian version (e.g. sid)
--arch=archname                 Sets the architecture (valid options: $valid_arches_str)
--outdir=dirname                Sets the folder where the downloads should go into
--download_suggested            Enables downloading suggested packages
-download_recommended           Enables recommended suggested packages
--dryrun                        Don't really download packages in the end, only simulate
--mirror_country=de,us,...      Sets the ftp server country to download from (default: de)
EOF

        if($exit) {
                print $str;
        } else {
                warn $str;
        }

        exit $exit;
}

sub analyze_args {
        foreach (@_) {
                if(m#^--debug$#) {
                        $options{debug} = 1;
                } elsif(m#^--download_suggested$#) {
                        $options{download_suggested} = 1;
                } elsif(m#^--download_recommended$#) {
                        $options{download_recommended} = 1;
                } elsif(m#^--dryrun$#) {
                        $options{dryrun} = 1;
                } elsif(m#^--mirror_country=(.*)$#) {
                        $options{mirror_country} = $1;
                } elsif(m#^--package=(.*)$#) {
                        $options{package} = $1;
                } elsif(m#^--version=(.*)$#) {
                        $options{version} = $1;
                } elsif(m#^--arch=(.*)$#) {
                        $options{arch} = $1;
                } elsif(m#^--outdir=(.*)$#) {
                        $options{outdir} = $1;
                } else {
                        warn_red "Unknown parameter $_";
                        _help(1);
                }
        }

        my $error = 0;
        if(!defined($options{package})) {
                warn_red "--package not defined";
                $error++;
        }

        if(!defined($options{arch})) {
                warn_red "--arch not defined";
                $error++;
        }

        if(!defined($options{version})) {
                warn_red "--version not defined";
                $error++;
        }


        if(!grep($_ eq $options{arch}, @valid_arch)) {
                warn_red "--arch=$options{arch} not valid (valid arches: $valid_arches_str)";
                $error++;
        }

        if(!$error && !defined($options{outdir})) {
                $options{outdir} = "$options{package}/$options{version}/$options{arch}";
                mkdir $options{package} unless -d $options{package};
                mkdir "$options{package}/$options{version}/" unless -d "$options{package}/$options{version}/";
                mkdir $options{outdir} unless -d $options{outdir};
                warn_red "--outdir not defined, using $options{outdir}";
        }

        if($error) {
                _help($error);
        }

        if(!-d $options{outdir}) {
                mkdir $options{outdir} || die $!;
        }
}

sub write_file {
        my $filename = shift,
        my $contents = shift;
        debug "write_file($filename, ...)";

        open my $fh, '>', $filename;
        print $fh $contents;
        close $fh;
}

sub read_file {
        my $file = shift;
        debug "read_file($file)";
        my $contents;
        open my $fh, '<', $file or die $!;
        while (<$fh>) {
                $contents .= $_;
        }
        close $fh;
        return $contents;
}

sub myget {
        my $url = shift;
        debug "myget($url)";

        my $get_cache_dir = '.cache/';
        mkdir $get_cache_dir unless -d $get_cache_dir;

        my $md5_url = md5_hex($url);

        my $cache_file = "$get_cache_dir$md5_url";

        my $contents = '';

        if(-e $cache_file) {
                debug "myget -> got $url from $cache_file";
                $contents = read_file($cache_file);
        } else {
                debug "myget -> DID NOT get $url from $cache_file, re-downloading it";
                $contents = get($url);
                write_file($cache_file, $contents);
        }

        return $contents;
}
