FROM mcr.microsoft.com/playwright:focal

WORKDIR /ms-playwright

COPY package.json .
COPY package-lock.json .

RUN npm install

COPY generate.js .
COPY wait-for-it.sh /usr/local/bin/wait-for-it
COPY retool-test.sh /usr/local/bin/retool-test

CMD tail -f /dev/null
