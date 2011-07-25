TMPFILE=$(mktemp -t cron)
echo "*/10 * * * * cd $2/current && /usr/local/bin/bundle exec rake -f $2/current/Rakefile update_twilio_stats RAILS_ENV=$1"
crontab -r
crontab $TMPFILE 
crontab -l
rm $TMPFILE
echo "Crontab added!"

