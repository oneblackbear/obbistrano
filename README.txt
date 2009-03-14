== Automated Server and application deployment

=== Server-wide setup

@cap host:setup -s h=xxxx@
Ensures that there is a setup for each app on the specified server.
Includes setup of a user, group, apache vhost, mysql login for each app.

@cap host:backup -s h=xxxx@
Trigger a backup of each application stored on the specified server.

@cap host:s3backup -s h=xxxx@
Triggers an Amazon S3 backup of the backup folder.



=== Application Level Setup

@cap app:deploy -s a=xxxx@


cap app:

