# Gallons Dockerfile
FROM rocker/shiny  

# I'm trying to instal every possible thing that may be needed
RUN apt-get update -qq && apt-get -y --no-install-recommends install \
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
	libxml2-dev \
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
	libssl-dev \
	libsqlite3-dev \
	libmariadbd-dev \
	libmariadb-client-lgpl-dev \
	libpq-dev \
	libssh2-1-dev \
	unixodbc-dev \
	libsasl2-dev
RUN mkdir -p /var/lib/shiny-server/bookmarks/shiny

# Download and install library
# 'dplyr','ggplot2', 'httr','jsonlite', 'lubridate'  - these are already in Tidyverse, unless things change
RUN R -e "install.packages(c('devtools','ggmap','data.table','knitr','kableExtra','png', 'gridExtra', \
'censusr','tigris','sp','tidycensus','leaflet','geosphere','googleway','ranger', 'xgboost', 'ggthemes', \
'rmarkdown', 'shiny','tidyverse','e1071','randomForest','shinythemes', 'tidytext', \
'topicmodels', 'wordcloud', 'AzureStor'), dependencies = c('Depends', 'Imports', 'LinkingTo'))"


COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

# REMOVE SAMPLE APPS
RUN rm -rf /srv/shiny-server/sample-apps
RUN find /srv/shiny-server/ -name '[0-9][0-9]_*/*' -delete
RUN find /srv/shiny-server/ -name '[0-9][0-9]_*' -exec rm -rv {} +
RUN rm /srv/shiny-server/index.html

# move apps (placed at root of ShinyServer) to where they will be served from
ADD ./yourApp /srv/shiny-server/yourApp
ADD ./anotherApp /srv/shiny-server/anotherApp

EXPOSE 3838
EXPOSE 8080
# EXPOSE 80

# the line below improves security but doesn't allow port 80...
USER shiny

CMD ["/usr/bin/shiny-server.sh"] 

