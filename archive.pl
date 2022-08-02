use strict;
use warnings;
use utf8;
use Getopt::Long;
use Twitter::API;
use JSON::XS;
use YAML::XS;
use Furl;
use File::Basename qw/basename/;
use File::Path qw/mkpath rmtree/;
use Archive::Zip qw/:ERROR_CODES :CONSTANTS/;
use feature qw/say/;

my $opt = sub {
    my %opt;
    my @options = (\%opt, qw/target=s/);
    GetOptions(@options) or die;
    \%opt;
}->();
my $config = YAML::XS::LoadFile 'config.yml';

my $target_screen_name = $opt->{target};
my $all_statuses = [];
my $max_id;
my $twitter = Twitter::API->new_with_traits(
    traits              => ['Enchilada', 'RateLimiting'],
    consumer_key        => $config->{credentials}{consumer_key},
    consumer_secret     => $config->{credentials}{consumer_secret},
    access_token        => $config->{credentials}{access_token},
    access_token_secret => $config->{credentials}{access_token_secret},
);

while (1) {
    my $statuses = $twitter->user_timeline({
        screen_name => $target_screen_name,
        defined($max_id) ? (max_id => $max_id) : (),
        include_rts => 1,
        count => 200,
        tweet_mode => 'extended'
    });
    last if scalar(@$statuses) < 2;
    push(@$all_statuses, @$statuses);
    say 'Got '. scalar(@$all_statuses). ' statuses.';
    $max_id = $statuses->[-1]{id_str};
    say 'Next: '. $max_id;
}

say 'Got all '. scalar(@$all_statuses). 'statuses';

{
    open my $fh, ">", 'statuses.json';
    print $fh encode_json $all_statuses;
    close $fh;
}

for my $status (@$all_statuses) {
    next unless ($status->{extended_entities});
    for my $medium (@{$status->{extended_entities}{media}}) {
        if ($medium->{type} eq 'photo') {
            my $url = $medium->{media_url_https};
            my $filename = basename($url);
            $url .= '?name=orig';
            download($url, $filename);
        }

        if ($medium->{type} eq 'animated_gif') {
            my $url = $medium->{video_info}{variants}[0]{url};
            my $filename = basename($url);
            download($url, $filename);
        }

        if ($medium->{type} eq 'video') {
            my $video_variants = $medium->{video_info}{variants};
            for (@$video_variants) { $_->{bitrate} = 0 unless $_->{bitrate} }
            my $url = (sort { $b->{bitrate} <=> $a->{bitrate} } @$video_variants)[0]{url};
            $url =~ s/\?.+//;
            my $filename = basename($url);
            download($url, $filename);
        }
    }
}

my $zip = Archive::Zip->new;
$zip->addFile('statuses.json');
$zip->addTree('media/', 'media/');
if ($zip->writeToFileNamed("tweet_archive_${target_screen_name}.zip") == AZ_OK) {
    say "ZIP archive created successfully!";
} else {
    warn "ZIP archive creation failed";
}

unlink 'statuses.json' if -f 'statuses.json';
rmtree 'media/' if -d 'media/';

sub download {
    my $url = shift;
    my $filename = shift;

    my $res = Furl->new->get($url);
    if ($res->code != 200 or $res->content =~ /timeout/) {
        warn "cannot download media: $url";
        return;
    }

    mkpath 'media' unless -d 'media';

    open my $fh, '>', 'media/'. $filename or die "cannot create file: media/$filename";
    print $fh $res->content;
    close $fh;
    return;
}
