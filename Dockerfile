FROM    centos:centos6

RUN     rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
RUN     yum install -y npm
RUN     yum install -y gcc make git

COPY . /src
RUN npm install -g coffee-script
RUN cd /src; npm install

WORKDIR /src

EXPOSE  8000

CMD ["coffee", "./pushd.coffee"]
