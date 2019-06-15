# R Shiny Server, on... Azure Container Instances, with Nginx and Certbot for SSL and Azure Pipelines for CI-CD

Even as a primarily Python Data Scientist, I have always liked R Shiny. I think it is the best way for a data scientist to deploy a web app for end users. Lots of features. Easy to use. 
I have deployed apps for end users both as desktop apps and to shinyapps.io. 
But recently I ran into a problem, which was that shinyapps.io did not offer enough RAM for one machine-learning report, which needed about 6 gbs of RAM. 
I also had getting a R Shiny Server on my long term to-do list - more control, more power, easier to coordinate multiple developer's apps.

But how to design this particular server? Well I had a lot to consider...

### My Requirements:
 * Must be able to host fairly resource intensive Shiny apps, but only for a handful of internal users.
 * Use Azure cloud for compute (because that's the company's primary cloud provider)
	* I prefer containers, although that wasn't a strict requirement
	* I also wanted serverless, so it would be possible to scale and move around more easily.
 * Deployable with Azure Pipelines for CI-CD
 * Secured with HTTPS/SSL Certificates with the option to allow access for only select IP addresses
	* And to have the certs auto-renew, I don't want to have to add new certs every x period of time.
 * Be easy enough to use than a data scientist can usually add their own app to deployment by themselves.
 * Be buildable by me, whose only experience in web developing was self-hosting Wordpress on a VM...
 * Be essentially zero maintenance, with strong version control. One of the reasons I like containers...
 * Be pretty cheap, not that my company can't pay plenty, but the odds of it existing many years in the future are much higher the cheaper it is.

### So, let's work through my thinking. 
I decided to use Shiny Server, the open source version, not the Enterprise version, because I don't particularly want to bother with getting a software license. 
More waiting, more probability the license is dropped at some point. 
There is another tool called Shiny Proxy which is open source, but it didn't seem appropriate for running inside a container itself. 
Shiny Server Open Source, by itself, would be fine if you didn't need the site to be encrypted, or to have access control, etc. 
Simply build the Shiny Server dockerfile, adjust the shiny-server.conf to port 80, and expose the port to the world.

Now, I needed something to manage SSL certificates and IP addresses, port forwarding, and all of that. 
Shiny Enterprise does offer many of those features, but I had already decided to go without, if possible. 
Instead, I went with having a Nginx container as a proxy server, and honestly it was probably nicer than using Enterprise Shiny Server, 
lots of customization, lots of community support, and free.

As for the SSL certificates themselves, I knew I could get signed certificates from IT, but I didn't really want to count on them being replaced every year. 
LetsEncrypt then, with its certbot tool is something I used before, and is very easy to use. It can easily be scheduled to auto-renew. 
Well not so easily in this case, but whatever. There is however, one big caveat, which is Certbot has to run from inside the IP address/DNS location for which it is certifying. 
Normally on a server that is easy to do, but I am going serverless which means configuration is a bit trickier. More on that to come.

Where we are now: Shiny Server for serving the Shiny Apps, Nginx for helping manage the web traffic, and Certbot for SSL, could be used almost anywhere. 
Installed as they are on a server. Installed inside containers on a VM using docker-compose. And of course, serverless cloud container orchestration, like Kubernetes. 

You probably don't need to be sold on containers in the present age, but since I am the only person at my company with containers in production - many others are working on getting there in IT, 
but they aren't there yet - I can still legitimately treat it as worth considering. 
Containers host an entire many operating system complete with all the packages you need. They have two main advantages:
1. being extremely portable. You can take your containers to any cloud provider, on premise, anywhere, and they will likely run
2. being isolated environments. Less worry over package conflicts. More security. Easier to understand than one messy system.

and more, but those are the main points to me here.

Full Kubernetes seemed a bit overkill for my case (a bit harder, more expensive, and I doubt I'll need multiple copies of containers), so I went with container instances 
(`Azure Container Instances,` `AWS ECS Container Instances,` and Google has something like I'm sure). 
Container instances are basically docker-compose but without worrying about the underlying VM. It makes them a bit cheaper, and there's less infastructure to maintain. 
I currently use Azure Container Instances for, hmm, yes, all of my production deployments personally - which are mostly batch python machine learning scripts. 
Given the current rate of development, it wouldn't surprise me if there's developments in Kubernetes over the next year or two which make that the easiest choice.

As for getting everything into production, I have rather become a devout follower of CI-CD pipelines. 
You have your GitHub (or other git) repo, and there you have all your code. And all of your technical documentation.
The CI-CD pipeline then, whenever you trigger it, or whenever you commit to master on git, magically makes all that code turn into the running production product.
Well, it's not magic, it's a bunch of .yaml that tells a VM to, in this case, build docker images, push them, and then run Azure commands to start the container group.
The beauty is you have one place with code/documentation -your GitHub repo. Another place has the deployment pathways. 
A final place (not discussed) has cohesive logging and monitoring. It makes it much easier for any person to step in, contribute, and maintain.

Finally we have Shiny Server, Nginx, and Certbot, in containers, hosted on Azure Container Instances, and deployed by Azure Pipelines. 
What's the one problem I had with this whole operation that I am not quite satisfied with? It's the certifcate renewals of Certbot. 
My problem is that the certbot container appears to interfere with the nginx container. I only need the certbot container to run for about 5 seconds every month or so. 
So my solution to this problem is to build the container group with certbot, wait a minute, delete the container group, and then rebuild without certbot. 
I then schedule this build, delete, rebuild in a pipeline to occur once a week, Sunday around 1 am. It works rather well, but isn't elegant.

One thing I still need to learn how to do better is manage secrets. I think some people get a little bit obsessive about hiding 'secrets' 
like API keys, in ways that really aren't that much more secure. I have yet to see a way that really keeps secrets secure in most cases.

A last detail is that the volumes I mount in my example are Azure File Shares. 
Some form of external storage outside the container group is needed, primarily for the SSL certificates and logs.
I also keep nginx configuration there, because I can then update that and restart the container group to get it active, without running the full pipeline.
 
FYI: It took me a full week of work to get this all figured out and deployed.

You can see more details in the linked GitHub's readme, which was built in a meandering fashion for users.
I primarily am sharing my code, because code shared like that, even with mediocre documentation, has been very helpful in my own work here.


 