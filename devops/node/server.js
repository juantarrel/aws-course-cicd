'use strict';

const express = require('express');
var fs = require('fs');

// Constants
const PORT = 80;
const HOST = '0.0.0.0';

// App
const app = express();
app.get('/', (req, res) => {
  res.send('Hello world\n');
});

app.get('/build-info', (req, res) => {
    fs.readFile('build-number', 'utf8', function(err, contents) {
        res.send(contents);
    });

});

app.listen(PORT, HOST);
console.log(`Running on http://${HOST}:${PORT}`);