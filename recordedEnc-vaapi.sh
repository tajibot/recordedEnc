#!/bin/sh

outfile=${1%.*}.mp4
sec=`awk "BEGIN{srand(); print int(rand()*100)%59+1;}"`
ffmpegbin="/home/htajima/bin/ffmpeg"
ts2enc="/home/htajima/bin/ts2enc-vaapi.pl"

# MP4 folder
mp4dir="/mnt/synology/tv"
gphotodir="/mnt/win177/tv"


#until [ ! `pidof -s ffmpeg` ]
#do
#    sleep ${sec}
#done

#/usr/local/bin/ts2enc.pl "$1" "${outfile}" > /dev/null 2>&1
#/usr/local/bin/ts2enc-vaapi.pl "$1" "${outfile}"  2>&1  |logger -p local1.info -i

#nice -n 15 $ts2enc -multi "$1" "${outfile}"  2>&1  |logger -p local1.info -i
nice -n 15 $ts2enc  "$1" "${outfile}"  2>&1  |logger -p local1.info -i



#nice -n 15 $ffmpegbin -vaapi_device /dev/dri/renderD128 -hwaccel vaapi -hwaccel_output_format vaapi -i $1 -vf 'format=nv12|vaapi,hwupload,scale_vaapi=w=1280:h=720' -c:v h264_vaapi -f mp4 -profile 100 -level 40 -qp 28 -threads 4 -aspect 16:9 -acodec libfdk_aac -ac 2 -ar 48000 -ab 192k ${outfile}  2>&1  |logger -p local1.info -i

#### 2pass ######
#nice -n 15 $ffmpegbin -y  -vaapi_device /dev/dri/renderD128 -hwaccel vaapi -hwaccel_output_format vaapi -i $1 -vf 'format=nv12|vaapi,hwupload,scale_vaapi=w=1280:h=720' -c:v h264_vaapi -f mp4 -profile 100 -level 40 -qp 28 -threads 4 -aspect 16:9 -pass 1 -acodec libfdk_aac -ac 2 -ar 48000 -ab 192k ${outfile}  2>&1  |logger -p local1.info -i && \
#nice -n 15 $ffmpegbin -y  -vaapi_device /dev/dri/renderD128 -hwaccel vaapi -hwaccel_output_format vaapi -i $1 -vf 'format=nv12|vaapi,hwupload,scale_vaapi=w=1280:h=720' -c:v h264_vaapi -f mp4 -profile 100 -level 40 -qp 28 -threads 4 -aspect 16:9 -pass 2 -acodec libfdk_aac -ac 2 -ar 48000 -ab 192k ${outfile}  2>&1  |logger -p local1.info -i


# copy MP4 file to Google Photo folder
cp ${outfile} ${gphotodir} 
# mv MP4 file to MP4 folder
mv ${outfile} ${mp4dir}

exit 0
