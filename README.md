# (Shiny) App Server with Shiny Server, Nginx, Certbot, on Azure Container Instances, Azure File Shares, and Azure Pipelines.
I'm posting this publically as 'food for thought' for anyone else doing a similar project. The one part I am unhappy with is SSL certificate renewal, which relies on an Azure pipeline running (weekly) to do add certbot container to the group, and then remove it. It works, but isn't pretty. That renewal pipeline is not included, but its identical to the pipeline here, less the docker build/push.

## Why Use R Shiny?
https://shiny.rstudio.com/gallery/

R Shiny makes deploying a data science web app very easy for non-web developers. Easy yes, but also extremely capable. You can make simple visualization dashboards -like Tableau or PowerBI- but with greater customizability if needed: fancy interactive figures, real-time data visualizations, even custom javascript. You can do all sorts of interactive maps using Leaflet, ggmaps, and so on. In particular you can make web apps that end-users can interact with to access machine learning. If users need to do manual inputs, upload files and have them processed by machine learning, and so on, you can handle that with Shiny. 

Shiny is best for internal use and lower volume apps. While you can scale this up - you could move this to Kubernetes for massive traffic of millions - if you have a use case where tons of people are going to be accessing your web app, probably best to have a web developer do it for you.

This current server build can actually host things beyond just are R Shiny if you need an easy and cheap place for secure connections. You could build another app (say, in Python) in the container group that is in it's own container. Expose it over a port that isn't already in use, and then have Nginx forward your unique `<this_domain>/yourApp/` to whatever port that is. But unless you already know what I'm talking about, I recommend you stick to R Shiny.

## Basic Use is EASY!
Take your Shiny App, developed and tested locally in RStudio, it should minimally have `/yourRepo/app.R` (or potentially the old two file ui.R and server.R) `/yourRepo/` may also have a bunch of other files like `.rda` files (or the less efficient .csv, etc) of models and data. It can have multiple directories inside it, but app.R should be at the highest level of your app repo. Look at, currently, GallonsApp or TankerTrackerApp as examples. Just copy and paste that repo into the ShinyServer repo (that's where you are now in GitHub).

After you've added your repo to GitHub, you'll definitely need one little change to the Dockerfile. If unsure, you can test this with docker, as shown shortly.
```
ADD ./gallonsApp /srv/shiny-server/gallonsApp
# more generally
ADD ./yourRepo /srv/shiny-server/yourAppName
```
This simply copies your app's folder, which you've added here in GitHub, to the place where Shiny looks to serve apps.

Go to Azure Pipelines, and click to run the ShinyServer pipeline. Viola! Shiny App is in production.

There is just one trickier thing with this deployment, which is installation of new R packages onto the server. This is done in the Dockerfile, where you can see currently installed packages. All of Tidyverse, as well as a number of other packages are installed already. **The containers run in Linux,** and you may need to `apt-get` some supporting apps to make it work. For example to use the `png` image package, I needed to apt-get `libtiff5-dev`. Usually a Google Search of "install <mypackage> on Ubuntu/Linux" will tell your pretty quickly what might be needed. Or don't do the Google Search, just add your packages to the Dockerfile, and test, seeing if the container builds successfully. If it does, you're probably good. If not, it tells you which packages failed. This dockerfile *should* already have the necessary installations for most common packages. 

If adding new packages, I strongly recommend further levels of testing, or else your Dockerfile will fail to build successfully. Don't worry, it's pretty easy but requires Docker installed. You can build and test the ShinyServer dockerfile on local as well - no need for nginx or certbot. Just **be very careful** what you mess with outside of /yourRepo/.
I run the below in Anaconda Prompt or the windows command prompt.
```
cd /<some_directories>/ShinyServer
docker build --tag=shinyserver .
docker run --rm -p 3838:3838 shinyserver
```
*Assuming the default port 3838 is being used.*
Open your browser to the url `localhost:3838` or `localhost:3838/yourAppName` 
If your browser opens your app, you are probably good to go. Sometimes not all the shiny app elements will work, this can be problems either with your app.R - test it more locally - or perhaps a failed package install in the dockerfile/docker build. 

## General Info
Right now, this a **Shiny Server** container with **Nginx** ('engine-x' proxy server) and **Certbot** (LetsEncrypt SSL certificate) sidecars. App folders can be placed inside this repository, and will be served by the Shiny Server - open source version. Nginx serves as a proxy server to redirect to SSL encrypted traffic, and manage other internet protocols. Nginx currently does not have its own image built here, an official dockerhub image is used directly and the configuration filed is mounted to it.

Currently CertBot is built into the container group by the pipeline, then the container group is rebuilt *without* certbot because certbot fights over the `80` and `443` ports, apparently, and even when it stops running after about 5 seconds -that's all it takes, the poor Nginx is too confused to work.

Nginx Logs are in Azure storage account **shinyserver** `nginx-conf/logs`. LetsEncrypt and Shiny logs are in the same storage account but in `shiny-logs` file share. Some logs are also in Azure Portal, Azure Container Instances, select the instance, go to 'Containers', click on the container and click on 'logs'. FYI feel free to use that same usvshinerserver storage account for your app's related blob storage, etc.

Currently this app blocks all non-USV IP addresses, you can adjust that by removing `deny all'` from part of the nginx.conf. You could also add new location blocks, allowing all traffic to some apps, and not others. 
Make sure to upload changes of `nginx.conf` to the Azure File Share `nginx-conf`. You *don't* need to rerun the pipeline to deploy changes just to `nginx.conf`. All you have to do is update the file share, then click start/stop in Azure Container Instances to restart the app.
Also currently Azure Automation Runbooks are used to turn the container off at night.

If you are doing any more complicated changes, you can fork this repo, adjust the DNS name label prefix to a new (I suggest usvshinerserver3), more below on that, and use that as DEV. A new pipeline for dev would be easy from a forked repo, as it auto-detects "azure-pipelines.yml." Use the same fileshares, except maybe the shinyserver-cert fileshare.

## Reconfiguring the Server is HARD!
Theoretically, just the Shiny Server container could be run. It could be exposed over the default port `3838` or another port as configured by `shiny-server.conf`. But corporate security wants it to be secured over HTTPS (encrypted) and with the option to block all non-USV ips. That's where Nginx and Certbot come in.
Nginx is primarily configured by nginx.conf *which is stored in an Azure File Share.* That `nginx.conf` file is where you edit IP address rules, server proxies, etc. You can and should edit nginx.conf here, but just upload that to the fileshare when you're ready.

Certbot is the tool which configures the LetsEncrypt SSL certificate. Here's the crazy thing about that - it *needs* to be in the container group to get the certificates as it has to be reachable at the DNS the container uses. However, in so being there it, unless I can find a hack around, blocks Nginx from working. So this way the container group has to be deployed with certbot, the certs updated, then redeployed without certbot once the certs are renewed. Ufda. 
Certbot's configurations are also stored as a `.tar.gz` file in Azure File Share, and unpacked from there. It has another file share which will be empty, which is used to host temporary files between it and nginx during the verification to receive certificates. 

I'm hoping this process gets easier as Azure roles out more features, but for the moment it is what it is. Azure App Services would make this easier, but is much more expensive to run on. A dedicated VM with Docker Compose would be fairly easily to transition this to - and that wouldn't need a certbot container, as it could just be handled on the VM and cron.

## Debugging: Certification is the most likely failure point.
Firstly, make sure that certificates exist in the file share store. If they don't exist, Nginx will fail to start. These guys:
`
/etc/nginx/certs/example.eastus.azurecontainer.io/fullchain.pem;
/etc/nginx/certs/example.eastus.azurecontainer.io/privkey.pem;
`
both of these are available in Azure Storage Account `nginx-conf` (ie `/certs/<domainname>/fullchain.pem`). If they are not there, **YOU MUST** make new temporary ones with `openssl req -x509 -nodes -newkey rsa:1024 -days 365 -keyout 'privkey.pem' -out 'fullchain.pem'` which is easiest with Linux. 
And yes, self-signed certificates will generate a giant "page is not secure!" warning in your browser, just add a security exception and ignore that for dev purposes. Get certbot working for the SSL which provides HTTPS.

Secondly, rerun the 'ShinyServerCertificateRenewal' pipeline. This should install new SSL certificates assuming no underlying errors in the containers. Thirdly, rerun the full ShinyServer pipeline, see if that fixes things.

If it still doesn't work, you'll need to track down the logs, locations mentioned above, and start reading. The logs in the Container Instances 'Containers' page on Azure Portal are usually best to start with. 
Making sure shiny server itself is working is the easiest - you can build and launch that Docker container locally, and see if it runs on localhost. It's logs are also pretty easy to see `Listening on ::3838` etc. 

Indeed, if you need a quick hack to get things running again, redirect `shiny-server.conf` off of port `8080` or `3838` to port `80`, and then remove both of the certbot and nginx images from **both** of the ACI command line deployment templates. Make sure to save that code you removed though, you'll want to put it back! Doing as I've said here removes the SSL/HTTPS encryption and security features, but should leave a functioning app. You can then make a duplicate pipeline of the original with a new DNS (I've used shinyserver3, etc) to debug on. Further down I list all the places where the DNS is hardcoded. ACI lets you easily create new DNS prefixes as long as they aren't used by someone else, just put a new name in the deployment code and it will work. Then test on this "DEV" DNS until you get it working, then point your fixed pipeline back at the original DNS and use it as the prod version.

#### Let's Encrypt
`certbot certonly --webroot -w /data/letsencrypt/ -d example.eastus.azurecontainer.io --non-interactive --agree-tos --email usvia@usventure.com`
`certbot renew`

DNS Name labels are hard-coded in:
```
nginx.conf (push to Azure File Share!)
	in server_names 
	in ssl certificate directories
deploy-aci.yaml
	in the prefix in dnsNameLabel
	in the certbot command
deploy-aci-removeCertbot.yaml
	in the prefix in dnsNameLabel
the SSL certificates themselves
```

#### deploy-aci.yaml references
https://github.com/MicrosoftDocs/azure-docs/issues/13140   
https://docs.microsoft.com/en-us/azure/templates/Microsoft.ContainerInstance/2018-10-01/containerGroups  

#### Could use GitHub repos mounted as volumes to the Shiny Server to auto-update apps
https://docs.microsoft.com/en-us/azure/container-instances/container-instances-volume-gitrepo

#### Mounting secret volumes
https://docs.microsoft.com/en-us/azure/container-instances/container-instances-volume-secret

#### Consider adding Nginx Amplify to monitor traffic
https://github.com/nginxinc/docker-nginx-amplify   
https://amplify.nginx.com/signup/

#### LetsEncrypt Certification
These work with docker or docker-compose, but could maybe be modified for ACI. Currently there's just not much documentation in that regard. Azure File Share might be one way to host certificates.  
https://medium.com/@pentacent/nginx-and-lets-encrypt-with-docker-in-less-than-5-minutes-b4b8a60d3a71   
https://medium.com/bros/enabling-https-with-lets-encrypt-over-docker-9cad06bdb82b   
https://medium.com/@samkreter/adding-ssl-tls-to-azure-container-instances-1e608a8f321c   
https://docs.microsoft.com/en-us/azure/container-instances/container-instances-container-group-ssl    
https://medium.com/@dbillinghamuk/certbot-certificate-verification-through-nginx-container-710c299ec549   
https://github.com/certbot/certbot/issues/4850

#### Deny/Allow IPs
Manually in Nginx: https://docs.nginx.com/nginx/admin-guide/security-controls/controlling-access-proxied-tcp/  
It might also be possible to configure Fail2Ban on the (Nginx?) container to add some control

###### For PEM versions of OpenSSL
```
openssl req -x509 -nodes -newkey rsa:1024 -days 365 -keyout 'privkey.pem' -out 'fullchain.pem'
```
Then place inside `/etc/nginx/certs/example.eastus.azurecontainer.io/` ie an azure file share

##### This is what a secret volume looks like
*it's in base 64*
```
  - secret:
      ssl.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUQ1ekNDQXM4Q0ZHV051UEdiait1WVBRa013OGg0bmpDc2IxMkhNQTBHQ1NxR1NJYjNEUUVCQ3dVQU1JR3YKTVFzd0NRWURWUVFHRXdKVlV6RUxNQWtHQTFVRUNBd0NWMGt4RVRBUEJnTlZCQWNNQ0VGd2NHeGxkRzl1TVJNdwpFUVlEVlFRS0RBcFZVeUJXWlc1MGRYSmxNUXN3Q1FZRFZRUUxEQUpKUVRFNE1EWUdBMVVFQXd3dmRYTjJjMmhwCmJubHpaWEoyWlhJdWJtOXlkR2hqWlc1MGNtRnNkWE11WVhwMWNtVmpiMjUwWVdsdVpYSXVhVzh4SkRBaUJna3EKaGtpRzl3MEJDUUVXRldOallYUnNhVzVBZFhOMlpXNTBkWEpsTG1OdmJUQWVGdzB4T1RBMk1URXdPVFV6TkRaYQpGdzB5TURBMk1UQXdPVFV6TkRaYU1JR3ZNUXN3Q1FZRFZRUUdFd0pWVXpFTE1Ba0dBMVVFQ0F3Q1Ywa3hFVEFQCkJnTlZCQWNNQ0VGd2NHeGxkRzl1TVJNd0VRWURWUVFLREFwVlV5QldaVzUwZFhKbE1Rc3dDUVlEVlFRTERBSkoKUVRFNE1EWUdBMVVFQXd3dmRYTjJjMmhwYm5selpYSjJaWEl1Ym05eWRHaGpaVzUwY21Gc2RYTXVZWHAxY21WagpiMjUwWVdsdVpYSXVhVzh4SkRBaUJna3Foa2lHOXcwQkNRRVdGV05qWVhSc2FXNUFkWE4yWlc1MGRYSmxMbU52CmJUQ0NBU0l3RFFZSktvWklodmNOQVFFQkJRQURnZ0VQQURDQ0FRb0NnZ0VCQUo4c3Z0bDFkbU9IUExLenl0YmYKeTJlSE1maFJGT2ZUSU1TSnlOYWF6amJSYWtkUlVtTHJpaXlxQ0JJT0pJS0N5S3pyYWgrSTBacHJ6RWJyUlFhNQptcFd2K2VGMGNIUWltZ0hGTllGVVYxVEZRb3RNNVVGY0I4Ynk4TkdwcHdWL0p4N1h4V0hiV1dtNEdEM1JjZDJICm5GRGc2STBwVlNWa3lOd3czRy8zWWk0cW85V1ZXYnBCaHIwSXpJbFRFUzAxQlFaTEZXcWtqeEl5NENpMU5KVnYKbDFjOVVabHp2ZnNnaW1waHVLUE11d3FGTk1PL05pZ0gvN01tZE12djFYcHYxa1U4NlFDelhybHpFaUFvRVlGcwo1bG1YTXBiWjZCdFNvTUp4YldNZCsrNTE4MkdrK3FMc3dkR1UrdFFIUzVBQkZabGN0OENmQ1MrVTJvS3RIblRnCmNVa0NBd0VBQVRBTkJna3Foa2lHOXcwQkFRc0ZBQU9DQVFFQWlCdG8rdVFjMVVHNmt6WU9qdmMyRWwvOGxheUQKaWI4eDNlKzJnZmZRUUpJRDRiTzVFWk9mcUdWcjdkd2dEeUM0d0E2d3VrVGdCMDg2dFJyRE02NVJKUmNKNDRybgpBVzJ1YUsyT01JVlI0WHpGQjZ6d2hnTk9vczNJQ05FbmdETFR5SVB1YmQ4eUtvNWFXYUNDZFRqczI2VmkyT0JTCmNYeW1zRW5KbjZDM3JVQ2pwUG5HeVpyeUhSVVdmTkt2NXg3NEN6K01mRlJvMTdwWUMwWVYvbHdkSlk0ZWx2YWkKVDVmNW1RSXI3Z1FHYU9WZGxPL05xSThhaHQ1L2Y1NkpqbHFlRElMYVduQ0NUL3Q1T2NpdTlDOFEyS3JJQlovZwpYZ0JxbEhGOVUzaDZuWVRkQUlkUlRMMzNKVjNtL09yUjJ2SzBtOUx4dnQvYkc1Ty92cG1lL1pRRjJBPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
      ssl.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2d0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktrd2dnU2xBZ0VBQW9JQkFRQ2ZMTDdaZFhaamh6eXkKczhyVzM4dG5oekg0VVJUbjB5REVpY2pXbXM0MjBXcEhVVkppNjRvc3FnZ1NEaVNDZ3NpczYyb2ZpTkdhYTh4Rwo2MFVHdVpxVnIvbmhkSEIwSXBvQnhUV0JWRmRVeFVLTFRPVkJYQWZHOHZEUnFhY0ZmeWNlMThWaDIxbHB1Qmc5CjBYSGRoNXhRNE9pTktWVWxaTWpjTU54djkySXVLcVBWbFZtNlFZYTlDTXlKVXhFdE5RVUdTeFZxcEk4U011QW8KdFRTVmI1ZFhQVkdaYzczN0lJcHFZYmlqekxzS2hUVER2ellvQi8rekpuVEw3OVY2YjlaRlBPa0FzMTY1Y3hJZwpLQkdCYk9aWmx6S1cyZWdiVXFEQ2NXMWpIZnZ1ZGZOaHBQcWk3TUhSbFByVUIwdVFBUldaWExmQW53a3ZsTnFDCnJSNTA0SEZKQWdNQkFBRUNnZ0VCQUk3UFIzKzFPbjI3aFFMVCtvWGtqZ3NacWdTZlFvRm4xRHRoWDNianQyWkoKWnZBTGp6NC9FMTVWUXg1bjMrdlVTUldUdFVnTHFmckJBcXNTUklEdkh6bHpoRjc1NkRiYUlKQzhEZkExNnBDYwoxc0pDUUdIdW51K3BZZFRLUUpiVzZSTnNCYVJ4ZDN3NWRrNW9UcCt5SHRZVm82K2F5TkRlNXJOZmh6ZFJuWjNLCnEyNEtrbHN0ZmdXREFiMm1TdUw3YnVRQWh3cFBFSjJHOGp5aEdET1hjQ3NXMjZsMmdqK1ZjUG1HS0xIVDlGUFkKaXBJdGJqb2FxWktEMHd2RzY4cWc1MVBST0ZsR01CMDlWcnRQaXE3VTh3YUhTWkJLQUI1SE5JbXBTSHJwT1NFcwpUTTRPR2JSWWM0bWVja2RLL1FhV2Y2U05EalNSYXpHa1dQc01rd3JYRklFQ2dZRUEwYUFmZXYrdFM4TWFQNGU4ClpJSU9Ld2lUQjh2S3dJaXNzS2x2MUJoWmppZmdBM2JsMTZLUHdxemE2ayswUStzVytoRDhRSjBwUm5UY3NjSjcKaEwvRVhwUnBMdmVZVkRrRm9hMWVsWmdPdjlhblNFMCtkRXhmRFBnWlNJSmpEMUZYTFJzWE5YaXpDZDhUb3YzZQpQalVDMThHUVhsU3JEWkp2U3E3RnBWdS9veEVDZ1lFQXdtTnBISk5yNVZDaEZpeTJoVE0xQlBjNG8zdmhhS3c1CjJlSzAwNTBUTzZwTFdlWEljbUcxdk1LYVFPWXl0WjVKekpIYS9IRGcwdFIxVFV0SXdNRTdlWHM2clNJUVQ4Qm8Kd1RJZVh0SjJ4Wm9ubXJ5SVRvOXZ4VXhZZmVMcjR4bFVEbjJrblo0SER0eTVJaU5DeTM0bDNWbGd1RDJnTUx3SAp4Qlc2SkFYVitya0NnWUE3UmQ2QTVmaTNXblI2a0VQcDI0aHNES0dlYTdacDJIdVQvR1Q5Z09FWnZCYXdoQmNiCmNRRGJXQXNTZy9VQjIyQ0UxdmFzd29PZ1Ezei8ybkVZcVN5NlhaYWNUREJMYUZBNlZnNVBtRTViV2pPMDB2cWMKNGRkaWtHaDl3emlGWlVlVUhudmloNzJBUmc2RVlPcE5ocW5HSGhwWFFmT1lBOWJxTkI3NDBjZVBNUUtCZ1FDWApCaTh5OFdKaGZodzVJeklIR0xxM2llOXFMS1A2ODl2YWFXVStCNHBhejdyTk5GWmdiNE9JRE5WVldNUExFUmliCkpES3o4R3Jyd2Y4RXQxbmx6L3NLTGZCdmRNaWhmWWFsbXUrM2tlS1BNVzVWck9abHl0RDJ3NUw0OHlWN2drRXAKSlBxUkxxYWpLRjk1bzFXUXpnaFRDYzY0TmNEUVBEWDRaVDBDSWJxV21RS0JnUUNTNmlsUk0zVENqa0JMZG9FNwo5bmQ0ZUdCK1BZM2k3ek5SUW0rWFcwTDhjNXB0d1l2YXdFajBGdDg2VXViSXpQK2xESXVUUU5XcjAycHY4YjVvCnhxS2szZmZEZkRJdTFCa0xEb21TUTE3K0FKUXhhYkRsU0wzTGdXYTVqak9xUloyeWc3RncyeUJ1cW54UUpGaUcKTy9abTl1SmVSS25EMit3RzJZcUhraUVCZVE9PQotLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tCg==
      nginx.conf: IyBuZ2lueCBDb25maWd1cmF0aW9uIEZpbGUNCiMgaHR0cHM6Ly93aWtpLm5naW54Lm9yZy9Db25maWd1cmF0aW9uDQoNCiMgUnVuIGFzIGEgbGVzcyBwcml2aWxlZ2VkIHVzZXIgZm9yIHNlY3VyaXR5IHJlYXNvbnMuDQp1c2VyIG5naW54Ow0KDQp3b3JrZXJfcHJvY2Vzc2VzIGF1dG87DQoNCmV2ZW50cyB7DQogIHdvcmtlcl9jb25uZWN0aW9ucyAxMDI0Ow0KfQ0KDQpwaWQgICAgICAgIC92YXIvcnVuL25naW54LnBpZDsNCg0KaHR0cCB7DQoNCiAgICAjUmVkaXJlY3QgdG8gaHR0cHMsIHVzaW5nIDMwNyBpbnN0ZWFkIG9mIDMwMSB0byBwcmVzZXJ2ZSBwb3N0IGRhdGENCiAgICBzZXJ2ZXIgew0KICAgICAgICBsaXN0ZW4gODAgZGVmYXVsdF9zZXJ2ZXI7DQogICAgICAgIGxpc3RlbiBbOjpdOjgwIGRlZmF1bHRfc2VydmVyOw0KICAgICAgICBzZXJ2ZXJfbmFtZSB1c3ZzaGlueXNlcnZlci5ub3J0aGNlbnRyYWx1cy5henVyZWNvbnRhaW5lci5pbzsNCgkJIyBzZXJ2ZXJfbmFtZSBsb2NhbGhvc3Q7DQogICAgICAgIHJldHVybiAzMDcgaHR0cHM6Ly8kaG9zdCRyZXF1ZXN0X3VyaTsNCiAgICB9DQoNCiAgICBzZXJ2ZXIgew0KICAgICAgICBsaXN0ZW4gWzo6XTo0NDMgc3NsOw0KICAgICAgICBsaXN0ZW4gNDQzIHNzbDsNCgkJc2VydmVyX25hbWUgdXN2c2hpbnlzZXJ2ZXIubm9ydGhjZW50cmFsdXMuYXp1cmVjb250YWluZXIuaW87DQogICAgICAgICMgc2VydmVyX25hbWUgbG9jYWxob3N0Ow0KDQogICAgICAgICMgUHJvdGVjdCBhZ2FpbnN0IHRoZSBCRUFTVCBhdHRhY2sgYnkgbm90IHVzaW5nIFNTTHYzIGF0IGFsbC4gSWYgeW91IG5lZWQgdG8gc3VwcG9ydCBvbGRlciBicm93c2VycyAoSUU2KSB5b3UgbWF5IG5lZWQgdG8gYWRkDQogICAgICAgICMgU1NMdjMgdG8gdGhlIGxpc3Qgb2YgcHJvdG9jb2xzIGJlbG93Lg0KICAgICAgICBzc2xfcHJvdG9jb2xzICAgICAgICAgICAgICBUTFN2MSBUTFN2MS4xIFRMU3YxLjI7DQoNCiAgICAgICAgIyBDaXBoZXJzIHNldCB0byBiZXN0IGFsbG93IHByb3RlY3Rpb24gZnJvbSBCZWFzdCwgd2hpbGUgcHJvdmlkaW5nIGZvcndhcmRpbmcgc2VjcmVjeSwgYXMgZGVmaW5lZCBieSBNb3ppbGxhIC0gaHR0cHM6Ly93aWtpLm1vemlsbGEub3JnL1NlY3VyaXR5L1NlcnZlcl9TaWRlX1RMUyNOZ2lueA0KICAgICAgICBzc2xfY2lwaGVycyAgICAgICAgICAgICAgICBFQ0RIRS1SU0EtQUVTMTI4LUdDTS1TSEEyNTY6RUNESEUtRUNEU0EtQUVTMTI4LUdDTS1TSEEyNTY6RUNESEUtUlNBLUFFUzI1Ni1HQ00tU0hBMzg0OkVDREhFLUVDRFNBLUFFUzI1Ni1HQ00tU0hBMzg0OkRIRS1SU0EtQUVTMTI4LUdDTS1TSEEyNTY6REhFLURTUy1BRVMxMjgtR0NNLVNIQTI1NjprRURIK0FFU0dDTTpFQ0RIRS1SU0EtQUVTMTI4LVNIQTI1NjpFQ0RIRS1FQ0RTQS1BRVMxMjgtU0hBMjU2OkVDREhFLVJTQS1BRVMxMjgtU0hBOkVDREhFLUVDRFNBLUFFUzEyOC1TSEE6RUNESEUtUlNBLUFFUzI1Ni1TSEEzODQ6RUNESEUtRUNEU0EtQUVTMjU2LVNIQTM4NDpFQ0RIRS1SU0EtQUVTMjU2LVNIQTpFQ0RIRS1FQ0RTQS1BRVMyNTYtU0hBOkRIRS1SU0EtQUVTMTI4LVNIQTI1NjpESEUtUlNBLUFFUzEyOC1TSEE6REhFLURTUy1BRVMxMjgtU0hBMjU2OkRIRS1SU0EtQUVTMjU2LVNIQTI1NjpESEUtRFNTLUFFUzI1Ni1TSEE6REhFLVJTQS1BRVMyNTYtU0hBOkFFUzEyOC1HQ00tU0hBMjU2OkFFUzI1Ni1HQ00tU0hBMzg0OkVDREhFLVJTQS1SQzQtU0hBOkVDREhFLUVDRFNBLVJDNC1TSEE6QUVTMTI4OkFFUzI1NjpSQzQtU0hBOkhJR0g6IWFOVUxMOiFlTlVMTDohRVhQT1JUOiFERVM6ITNERVM6IU1ENTohUFNLOw0KICAgICAgICBzc2xfcHJlZmVyX3NlcnZlcl9jaXBoZXJzICBvbjsNCg0KICAgICAgICAjIE9wdGltaXplIFNTTCBieSBjYWNoaW5nIHNlc3Npb24gcGFyYW1ldGVycyBmb3IgMTAgbWludXRlcy4gVGhpcyBjdXRzIGRvd24gb24gdGhlIG51bWJlciBvZiBleHBlbnNpdmUgU1NMIGhhbmRzaGFrZXMuDQogICAgICAgICMgVGhlIGhhbmRzaGFrZSBpcyB0aGUgbW9zdCBDUFUtaW50ZW5zaXZlIG9wZXJhdGlvbiwgYW5kIGJ5IGRlZmF1bHQgaXQgaXMgcmUtbmVnb3RpYXRlZCBvbiBldmVyeSBuZXcvcGFyYWxsZWwgY29ubmVjdGlvbi4NCiAgICAgICAgIyBCeSBlbmFibGluZyBhIGNhY2hlIChvZiB0eXBlICJzaGFyZWQgYmV0d2VlbiBhbGwgTmdpbnggd29ya2VycyIpLCB3ZSB0ZWxsIHRoZSBjbGllbnQgdG8gcmUtdXNlIHRoZSBhbHJlYWR5IG5lZ290aWF0ZWQgc3RhdGUuDQogICAgICAgICMgRnVydGhlciBvcHRpbWl6YXRpb24gY2FuIGJlIGFjaGlldmVkIGJ5IHJhaXNpbmcga2VlcGFsaXZlX3RpbWVvdXQsIGJ1dCB0aGF0IHNob3VsZG4ndCBiZSBkb25lIHVubGVzcyB5b3Ugc2VydmUgcHJpbWFyaWx5IEhUVFBTLg0KICAgICAgICBzc2xfc2Vzc2lvbl9jYWNoZSAgICBzaGFyZWQ6U1NMOjEwbTsgIyBhIDFtYiBjYWNoZSBjYW4gaG9sZCBhYm91dCA0MDAwIHNlc3Npb25zLCBzbyB3ZSBjYW4gaG9sZCA0MDAwMCBzZXNzaW9ucw0KICAgICAgICBzc2xfc2Vzc2lvbl90aW1lb3V0ICAyNGg7DQoNCg0KICAgICAgICAjIFVzZSBhIGhpZ2hlciBrZWVwYWxpdmUgdGltZW91dCB0byByZWR1Y2UgdGhlIG5lZWQgZm9yIHJlcGVhdGVkIGhhbmRzaGFrZXMNCiAgICAgICAga2VlcGFsaXZlX3RpbWVvdXQgMzAwOyAjIHVwIGZyb20gNzUgc2VjcyBkZWZhdWx0DQoNCiAgICAgICAgIyByZW1lbWJlciB0aGUgY2VydGlmaWNhdGUgZm9yIGEgeWVhciBhbmQgYXV0b21hdGljYWxseSBjb25uZWN0IHRvIEhUVFBTDQogICAgICAgIGFkZF9oZWFkZXIgU3RyaWN0LVRyYW5zcG9ydC1TZWN1cml0eSAnbWF4LWFnZT0zMTUzNjAwMDsgaW5jbHVkZVN1YkRvbWFpbnMnOw0KDQogICAgICAgIHNzbF9jZXJ0aWZpY2F0ZSAgICAgIC9ldGMvbmdpbngvc3NsLmNydDsNCiAgICAgICAgc3NsX2NlcnRpZmljYXRlX2tleSAgL2V0Yy9uZ2lueC9zc2wua2V5Ow0KDQogICAgICAgIGxvY2F0aW9uIC8gew0KICAgICAgICAgICAgcHJveHlfcGFzcyBodHRwOi8vbG9jYWxob3N0OjgwODA7ICMgIHJlcGxhY2UgcG9ydCBpZiBhcHAgbGlzdGVucyBvbiBwb3J0IG90aGVyIHRoYW4gODA4MA0KICAgICAgICAgICAgDQogICAgICAgICAgICBwcm94eV9zZXRfaGVhZGVyIENvbm5lY3Rpb24gIiI7DQogICAgICAgICAgICBwcm94eV9zZXRfaGVhZGVyIEhvc3QgJGhvc3Q7DQogICAgICAgICAgICBwcm94eV9zZXRfaGVhZGVyIFgtUmVhbC1JUCAkcmVtb3RlX2FkZHI7DQogICAgICAgICAgICBwcm94eV9zZXRfaGVhZGVyIFgtRm9yd2FyZGVkLUZvciAkcmVtb3RlX2FkZHI7DQogICAgICAgIH0NCiAgICB9DQp9
    name: nginx-config
```