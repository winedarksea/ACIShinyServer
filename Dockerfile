FROM rocker/shiny  

# I'm installing every possiblea thing! Probably could clean this up a bit.
RUN apt-get update && apt-get install -y \
	apt-transport-https \
	build-essential \
	gcc \
	pandoc \
	pandoc-citeproc \
	libcurl4-openssl-dev \
	libv8-3.14-dev \
	libudunits2-dev \
	libcairo2-dev \
	libxt-dev \
	libxml2 libxml2-dev \
	libtiff5-dev \
	gdebi-core \
	libgdal-dev \
	gsl-bin \
	libgsl0-dev \
	cmake \
	openjdk-8-jre \
	wget \
	libjq-dev \
	r-base-dev \
	libssl-dev 
RUN mkdir -p /var/lib/shiny-server/bookmarks/shiny

# Download and install library, "tidyverse" alone might be good enough to start with.
RUN R -e "install.packages(c('devtools','tidyverse','dplyr','ggplot2', 'ggmap', 'httr','jsonlite', \
'data.table','knitr','kableExtra','png','censusr','tigris','sp','tidycensus', \
'leaflet','geosphere','googleway','ranger', 'xgboost', 'ggthemes', 'rmarkdown', 'shiny'), repos='http://cran.rstudio.com/')"

COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

RUN rm -rf /srv/shiny-server/sample-apps
RUN rm /srv/shiny-server/index.html

ADD ./SampleApp /srv/shiny-server/SampleApp


EXPOSE 3838
EXPOSE 8080
# EXPOSE 80

# the line below improves security but doesn't allow port 80...
USER shiny

CMD ["/usr/bin/shiny-server.sh"] 


# docker run --rm -p 3838:3838 gallons  
