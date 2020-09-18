FROM node:14

#Install netcat

RUN apt-get update && \
    apt-get install -y netcat && \
    apt-get clean

WORKDIR /source
ENV PATH /source/node_modules/.bin:$PATH

COPY . .

# Install truffle
RUN npm install truffle

RUN npm install

ENTRYPOINT "/source/entrypoint.sh"