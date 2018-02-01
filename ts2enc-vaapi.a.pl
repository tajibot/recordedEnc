#!/usr/bin/perl

use strict;
use warnings;

use File::Basename qw/basename/;
use Getopt::Long;

my %opts;
my $script_name = basename $0;

GetOptions( \%opts, qw( aspect|a=s size|s=s quality|q=i copy interval|i=s mono=s multi speed=f fpre|f=s two tune=s vol=s crop|c=s vbr=s help|h ) ) 
    or die "Error(GetOptions)\n";

$SIG{'INT'}  = \&handler;
$SIG{'KILL'} = \&handler;

# ユーザー設定
my $ffmpeg_cmd  = "/home/htajima/bin/ffmpeg";
my $ffprobe_cmd = "/home/htajima/bin/ffprobe";
#my $preset_file = "/usr/local/etc/ts2enc.ffpreset";
#
#my $opt0 = "-y";
my $opt0 = "-y -vsync 1";
#my $opt0 = "-fflags +discardcorrupt -analyzeduration 120M -probesize 120M -y -vsync 1";

my $reso_large = "w=1280:h=720"; # 自動判定時の出力解像度(大)
my $reso_small = "w=720:h=480";  # 自動判定時の出力解像度(小)
#my $quality = 20;      # CRF値(画質, 0-51の範囲指定, 値が小さいほど高画質)
my $quality = 28;      # CRF値(画質, 0-51の範囲指定, 値が小さいほど高画質)
#my $quality = 0;      # CRF値(画質, 0-51の範囲指定, 値が小さいほど高画質)
#my $quality = 30;      # CRF値(画質, 0-51の範囲指定, 値が小さいほど高画質)
my $v_brate = "1000k"; # 動画ビットレート ※ 2-pass時のみ使用
my $a_brate = "192k";  # 音声ビットレート

# 音声コーデック設定
#my $acodec_param = "libfdk_aac -ac 2 -ar 48000 -ab $a_brate -async 100";
my $acodec_param = "libfdk_aac -ac 2 -ar 48000 -ab $a_brate -async 1";

# VAAPI
#my $vaapi_param1 = "-vaapi_device /dev/dri/renderD128 -hwaccel vaapi -hwaccel_output_format vaapi";
#my $vaapi_param1 = "-init_hw_device vaapi=intel:/dev/dri/renderD128 -hwaccel vaapi -hwaccel_output_format vaapi -hwaccel_device intel";
my $vaapi_param1 = "-init_hw_device vaapi=intel:/dev/dri/renderD128 -hwaccel_output_format vaapi -hwaccel_device intel";
my $filter = "-filter_hw_device intel";
#my $vaapi_param2 = "deinterlace_vaapi,format=nv12|vaapi,hwupload";
#my $vaapi_param2 = "deinterlace_vaapi,format=nv12|vaapi,hwupload,scale_vaapi=";
#my $vaapi_param2 = "deinterlace_vaapi=rate=field:auto=1,format=nv12|vaapi,hwupload,scale_vaapi=";
my $vaapi_param2 = "format=nv12|vaapi,hwupload,scale_vaapi=";
#my $vaapi_param3 = "-c:v h264_vaapi -profile:v 100 -level 40";
#my $vaapi_param3 = "-c:v h264_vaapi -level 40";
#my $vaapi_param3 = "-c:v h264_vaapi -level 40 -movflags faststart";
#my $vaapi_param3 = "-c:v h264_vaapi -profile:v 100 -level 40 -movflags faststart";
#my $vaapi_param3 = "-c:v h264_vaapi -profile:v 100 -level 40 -segment_format_options movflags=+faststart";
#my $vaapi_param3 = "-c:v h264_vaapi -profile:v 77 -level 31";
my $vaapi_param3 = "-c:v h264_vaapi -profile:v 77 -level 40 -segment_format_options movflags=+faststart";
my $thread_num = 4;

my @vf_opts = ();
my @af_opts = ();

sub usage {
    print <<END;
# Usage:
#   FFmpeg H.264変換補助スクリプト
# 
# 書式
#   $script_name [options] infile outfile
# 
# オプション
#   -h, -help 本内容の表示
# 
# 一般
#   -i, -interval hh:mm:ss-hh:mm:ss
#                           開始終了時間を指定して動画を切り出す(小数秒まで指定可)
#   -copy                   -i指定時のみ動作、入力ファイルを時間指定で切り出しコピー
#   -speed <float>          再生速度倍率を少数で指定(音程維持)
# 
# 映像
#   -s, -size w=1111:h=2222 出力解像度(例：w=1280:h=720)
#   -q, -quality <int>      画質、範囲0から51の整数、小さいほど高画質(デフォルト値25)
#   -a, -aspect 16:9|4:3    アスペクト比
#   -f, -fpre <file>        プリセットファイル
#   -tune <tune param>      チューニング設定(例：film, animation, grain)
#   -two                    2-passエンコードを実行
#   -vbr <video bps>        動画のビットレート、2-pass時のみ使用
#   -c, -crop W:H:X:Y       映像の出力範囲(例： 1080:1080:180:0)
#                            単位：ピクセル
#                             W: 出力サイズ、横幅
#                             H: 出力サイズ、高さ
#                             X: 左上隅原点からの横軸座標
#                             Y: 左上隅原点からの縦軸座標
# 
# 音声
#   -mono main|sub|both     2ヶ国語(モノラル主副音声)指定
#                             main  主音声のみ使用
#                             sub   副音声のみ使用
#                             both  主副音声を別トラックとして分離
#   -multi                  多重音声(ステレオ二重音声)指定
#   -vol <float|int dB>     音量を指定、少数で倍率指定、dBで微調整(例：0.5, -5dB)
# 
# デフォルトエンコード動作
#   － 映像
#     出力解像度            自動判定、入力解像度幅が720以下なら720x480、それ以外は1280x720
#     画質(CRF値)           $quality
#     アスペクト比          16:9
#     エンコード回数        1-pass
#   － 音声
#     タイプ                AAC
#     Ch数                  2ch
#     周波数                48kHz
#     ビットレート          $a_brate
END
}


if ( exists $opts{'help'} ) {
    &usage();
    exit 0;
}

# 引数ファイル指定
if ( $#ARGV < 1 ) {
    &usage();
    exit 1;
}

my $input_file  = $ARGV[0];
my $output_file = $ARGV[1];


# アスペクト比指定
my $aspect_param = "16:9";
if ( exists $opts{'aspect'} ) {
    $aspect_param = $opts{'aspect'};
}


# 出力解像度指定
my $size;
if ( exists $opts{'size'} ) {
    $size = $opts{'size'};
} else {
    my $width = `$ffprobe_cmd -v 0 -show_streams -of flat=s=_:h=0 "$input_file" | grep stream_0_width | awk -F= '{print \$2}'`;

    chomp($width);

    die "infile: 入力ファイルの解像度が不明です!" unless ( length($width) );

    if ( $width > 720 ) {
	$size = $reso_large;
    } else {
	$size = $reso_small;
    }
}


# 画質指定
if ( exists $opts{'quality'} ) {
    $quality = $opts{'quality'};
}


# チューニング指定
my $tune = "";
if ( exists $opts{'tune'} ) {
    $tune = "-tune ";
    $tune .= $opts{'tune'};
}


# 動画ビットレート指定
if ( exists $opts{'vbr'} ) {
    $v_brate = $opts{'vbr'};
}


# 時間指定の切り出し指定
my $time_opt = "";
if ( exists $opts{'interval'} ) {
    my ($stime, $etime) = split('-', $opts{'interval'});

    if ( $stime !~/^[\d]{2}:[\d]{2}:[\d]{2}\.?[\d]*$/ ||
	 $etime !~/^[\d]{2}:[\d]{2}:[\d]{2}\.?[\d]*$/ )
    {
	die "interval: 時間指定に誤りがあります!";
    }

    $time_opt = "-ss $stime -to $etime";
}


# 2ヶ国語(モノラル主副音声)指定
my $ffmpeg_front_opt = "";
if ( exists $opts{'mono'} ) {
    my $mono = $opts{'mono'};

    if ( $mono eq "main" || $mono eq "sub" ) {
	$ffmpeg_front_opt .= "-dual_mono_mode $mono ";
    } elsif ( $mono eq "both" ) {
	$acodec_param .= " -filter_complex channelsplit";
    } else {
	die "mono: 2ヶ国語の指定に誤りがあります!";
    }
}


# 多重音声(ステレオ二重音声)指定
my $multi_track = "";
if ( exists $opts{'multi'} ) {
    $multi_track = "-map 0:0 -map 0:1 -map 0:2";
}


# 倍速変換指定
if ( exists $opts{'speed'} ) {
    my $speed = $opts{'speed'};

    push(@vf_opts, "setpts=PTS/$speed");
    push(@af_opts, "atempo=$speed");
}


# プリセットファイル指定
#if ( exists $opts{'preset'} ) {
#    $preset_file = $opts{'preset'};
#}


# 音量指定
if ( exists $opts{'vol'} ) {
    my $vol = $opts{'vol'};

    push(@af_opts, "volume=$vol");
}


# 額縁削除指定
if ( exists $opts{'crop'} ) {
    my $crop = $opts{'crop'};

    if ( $crop !~ /^[0-9]+:[0-9]+:[0-9]+:[0-9]+$/ ) {
	die "crop: 出力範囲指定に誤りがあります!";
    }

    push(@vf_opts, "crop=$crop"); 
}


# 時間切り出し処理
my $halfway_file = "";
if ( length($time_opt) ) {
    if ( exists $opts{'copy'} ) {
	$halfway_file = $output_file;
    } else {
	$halfway_file = $input_file;
	$halfway_file .= "_tmp.ts";
    }

    system("$ffmpeg_cmd -i \"$input_file\" $time_opt $multi_track -c copy \"$halfway_file\"");
    die "時間による動画の切り出しに失敗しました!" if ( $? != 0 );

    exit 0 if ( exists $opts{'copy'} );

    $input_file = $halfway_file;
}

my $vf_opt;
if ( $#vf_opts >= 0 ) {
    $vf_opt = '-vf "';
    $vf_opt .= join(',', @vf_opts);
    $vf_opt .= '"';
}

my $af_opt;
if ( $#af_opts >= 0 ) {
    $af_opt = '-af "';
    $af_opt .= join(',', @af_opts);
    $af_opt .= '"';
}


my $trans_cmd;
if ( exists $opts{'two'} ) {
    # 2-pass処理
    $trans_cmd  = "$ffmpeg_cmd -y $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" -vf '${vaapi_param2}${size}' $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -pass 1 -acodec $acodec_param $multi_track $vf_opt $af_opt -f mp4 /dev/null";
    $trans_cmd .= " && ";
    $trans_cmd .= "$ffmpeg_cmd $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" -vf '${vaapi_param2}${size}' $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -pass 2 -acodec $acodec_param $multi_track $vf_opt $af_opt \"$output_file\"";
} else {
    # 1-pass処理
#    $trans_cmd  = "$ffmpeg_cmd $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" -vf '${vaapi_param2}${size}' -f mp4 $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -acodec $acodec_param $multi_track $vf_opt $af_opt  -pix_fmt yuv420p -ss 00:00:00 -to 00:05:00 \"$output_file\"";
#    $trans_cmd  = "$ffmpeg_cmd $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" -vf '${vaapi_param2}${size}' -f mp4 $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -acodec $acodec_param $multi_track $vf_opt $af_opt  -ss 00:00:00 -to 00:05:00 \"$output_file\"";
#    $trans_cmd  = "$ffmpeg_cmd $opt0 $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" -vf '${vaapi_param2}' -f mp4 $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -acodec $acodec_param $multi_track $vf_opt $af_opt  -ss 00:00:00 -to 00:02:00 \"$output_file\"";
#    $trans_cmd  = "$ffmpeg_cmd $opt0 $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" -vf '${vaapi_param2}${size}' -f mp4 $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -acodec $acodec_param $multi_track  -ss 00:00:00 -to 00:02:00 \"$output_file\"";
#    $trans_cmd  = "$ffmpeg_cmd $opt0 $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" -vf '${vaapi_param2}${size}' -f mp4 $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -acodec $acodec_param $multi_track $vf_opt $af_opt  -ss 00:00:00 -to 00:02:00 \"$output_file\"";
    $trans_cmd  = "$ffmpeg_cmd $opt0 $ffmpeg_front_opt $vaapi_param1 -i \"$input_file\" $filter -vf '${vaapi_param2}${size}' -f mp4 $vaapi_param3 -qp $quality -threads $thread_num -aspect $aspect_param -acodec $acodec_param $multi_track $vf_opt $af_opt  -ss 00:00:00 -to 00:02:00 \"$output_file\"";
}

print "--------------------------------------------------\n";
print "実行内容 : ", $trans_cmd, "\n";
print "--------------------------------------------------\n";
system($trans_cmd);

&handler();

sub handler {
    if ( -f $halfway_file ) {
	unlink($halfway_file);
    }

    if ( exists $opts{'two'} ) {
	foreach ( glob("ffmpeg2pass-*.log*") ) {
	    unlink($_);
	}
    }

    if ( exists $opts{'mono'} ) {
	unlink("channelsplit");
    }
}
