#!/usr/bin/env perl
use Modern::Perl;
use File::Basename qw( dirname basename );
use File::Path qw( make_path );
use File::Copy qw( copy );
use File::Spec;
use File::Glob qw( bsd_glob );

my $koha_dir = $ARGV[0] // '/kohadevbox/koha';
say "[build-alpine-package] Koha source directory: $koha_dir";

unless ( -d $koha_dir ) {
    say "[build-alpine-package] WARNING: Koha directory not found at $koha_dir; skipping build-time staging.";
    exit 0;
}

my $install_manifest = "$koha_dir/debian/koha-common.install";
unless ( -f $install_manifest ) {
    say "[build-alpine-package] WARNING: Manifest not found at $install_manifest; skipping build-time staging.";
    exit 0;
}

say "[build-alpine-package] Staging Koha assets from $koha_dir into Alpine system directories...";

# The Debian install manifest treats these htdocs destinations as directories.
make_path('/usr/share/koha/intranet/htdocs', '/usr/share/koha/opac/htdocs');

# 1. Parse debian/koha-common.install manifest
open my $fh, '<', $install_manifest or die "Cannot open $install_manifest: $!\n";

while ( my $line = <$fh> ) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;
    next if !$line || $line =~ /^#/;

    my ( $from, $to ) = split /\s+/, $line, 2;
    next unless $to;
    next if $from =~ m|/tmp/|;
    next if $from =~ m|/tmp_docbook/|;

    $to = "/$to" unless $to =~ m|^/|;

    my @sources = bsd_glob("$koha_dir/$from");
    @sources = ("$koha_dir/$from") if !@sources && -e "$koha_dir/$from";

    for my $src (@sources) {
        next unless -e $src;
        if ( -d $src ) {
            make_path($to) unless -d $to;
            system("cp -a $src/* $to/ 2>/dev/null") if bsd_glob("$src/*");
        } else {
            if ( -d $to || $to =~ m|/$| ) {
                make_path($to) unless -d $to;
                my $dest_file = File::Spec->catfile( $to, basename($src) );
                system("cp -a '$src' '$dest_file'");
            } else {
                my $dest_dir = dirname($to);
                make_path($dest_dir) unless -d $dest_dir;
                system("cp -a '$src' '$to'");
            }
        }
    }
}
close $fh;

# 2. Stage core Koha application structure if building from source checkout
if ( -d "$koha_dir/koha-tmpl" ) {
    make_path('/usr/share/koha/intranet/htdocs', '/usr/share/koha/opac/htdocs');
    system("cp -a $koha_dir/koha-tmpl/intranet-tmpl/* /usr/share/koha/intranet/htdocs/ 2>/dev/null");
    system("cp -a $koha_dir/koha-tmpl/opac-tmpl/* /usr/share/koha/opac/htdocs/ 2>/dev/null");
}

if ( -d "$koha_dir/C4" && -d "$koha_dir/Koha" ) {
    make_path('/usr/share/koha/lib');
    system("cp -a $koha_dir/C4 /usr/share/koha/lib/");
    system("cp -a $koha_dir/Koha /usr/share/koha/lib/");
}

if ( -d "$koha_dir/misc/search_tools" ) {
    make_path('/usr/share/koha/bin/search_tools');
    my $copy_status = system(
        'cp', '-a', "$koha_dir/misc/search_tools/.", '/usr/share/koha/bin/search_tools/'
    );
    die "Cannot stage Koha search tools (cp status $copy_status)\n" if $copy_status != 0;
}

if ( -d "$koha_dir/etc/zebradb" ) {
    make_path('/etc/koha/zebradb');
    system("cp -a $koha_dir/etc/zebradb/* /etc/koha/zebradb/ 2>/dev/null");
}

if ( -d "$koha_dir/etc/z3950" ) {
    make_path('/etc/koha/z3950');
    system("cp -a $koha_dir/etc/z3950/* /etc/koha/z3950/ 2>/dev/null");
}

# 3. Stage administrative scripts to /usr/sbin
if ( -d "$koha_dir/debian/scripts" ) {
    make_path('/usr/sbin', '/usr/share/koha/bin');
    system("cp -a $koha_dir/debian/scripts/koha-* /usr/sbin/ 2>/dev/null");
    system("chmod 0755 /usr/sbin/koha-* 2>/dev/null");
    if ( -f "$koha_dir/debian/scripts/koha-functions.sh" ) {
        system("cp -a $koha_dir/debian/scripts/koha-functions.sh /usr/share/koha/bin/");
    }
}

# 4. Copy Debian system files into /etc/
my %system_files = (
    'koha-common.bash-completion' => '/etc/bash_completion.d/koha-common',
    'koha-common.cron.d'          => '/etc/cron.d/koha-common',
    'koha-common.cron.daily'      => '/etc/cron.daily/koha-common',
    'koha-common.cron.hourly'     => '/etc/cron.hourly/koha-common',
    'koha-common.cron.monthly'    => '/etc/cron.monthly/koha-common',
    'koha-common.default'         => '/etc/default/koha-common',
    'koha-common.init'            => '/etc/init.d/koha-common',
    'koha-common.logrotate'       => '/etc/logrotate.d/koha-common'
);

make_path('/etc/bash_completion.d', '/etc/cron.d', '/etc/cron.daily', '/etc/cron.hourly', '/etc/cron.monthly', '/etc/default', '/etc/init.d', '/etc/logrotate.d', '/etc/koha');

while ( my ( $deb_file, $target ) = each %system_files ) {
    my $src = "$koha_dir/debian/$deb_file";
    if ( -f $src ) {
        system("cp -a '$src' '$target'");
    }
}

# koha-shell starts commands with PERL5LIB from koha-common.default. Alpine
# installs Koha's dependencies in a local::lib and keeps its source in /kohadevbox.
my $koha_defaults = '/etc/default/koha-common';
if ( -f $koha_defaults ) {
    open my $defaults_in, '<', $koha_defaults
        or die "Cannot open $koha_defaults: $!\n";
    local $/;
    my $defaults_content = <$defaults_in>;
    close $defaults_in or die "Cannot close $koha_defaults: $!\n";

    my ($perl5lib) = $defaults_content =~ /^PERL5LIB=(.*)$/m;
    die "PERL5LIB is missing from $koha_defaults\n" unless defined $perl5lib;
    $perl5lib =~ s/^\s*["']//;
    $perl5lib =~ s/["']\s*$//;
    my @alpine_perl5lib = (
        '/opt/koha-perl/lib/perl5',
        '/kohadevbox/koha/lib',
        '/kohadevbox/koha',
    );
    my %seen = map { $_ => 1 } @alpine_perl5lib;
    my @remaining_perl5lib = grep { length && !$seen{$_}++ } split /:/, $perl5lib;
    my @perl5lib = ( @alpine_perl5lib, @remaining_perl5lib );
    my $perl5lib_joined = join ':', @perl5lib;
    $defaults_content =~ s/^PERL5LIB=.*$/PERL5LIB="$perl5lib_joined"/m;

    open my $defaults_out, '>', $koha_defaults
        or die "Cannot write $koha_defaults: $!\n";
    print {$defaults_out} $defaults_content
        or die "Cannot write $koha_defaults: $!\n";
    close $defaults_out or die "Cannot close $koha_defaults: $!\n";
}

# Copy Apache templates
if ( -d "$koha_dir/debian/templates" ) {
    system("cp -a $koha_dir/debian/templates/apache-shared*.conf /etc/koha/ 2>/dev/null");
}

# 5. Generate manpages
if ( -d "$koha_dir/debian/docs" ) {
    make_path('/usr/share/man/man8');
    system("xsltproc --output /usr/share/man/man8/ /usr/share/xml/docbook/stylesheet/docbook-xsl-ns/manpages/docbook.xsl $koha_dir/debian/docs/*.xml 2>/dev/null");
    system("rm -f /usr/share/man/man8/koha-*.8.gz 2>/dev/null");
    system("gzip -f /usr/share/man/man8/koha-*.8 2>/dev/null");
}

say "[build-alpine-package] Build-time asset staging completed successfully.";
exit 0;
