const https = require('https');
const http = require('http');
const forge = require('node-forge');
const fs = require('fs');
const zlib = require('zlib');
const xml2js = require('xml2js');
var xmlParser = new xml2js.Parser();

const buildCncAuth = function(serverInfo) {
    const now = new Date();
    const dateStr = now.toUTCString();
    const hmac = forge.hmac.create();
    hmac.start('sha1', serverInfo.secretKey);
    hmac.update(dateStr);
    const d = hmac.digest();
    const b64passwd = forge.util.encode64(d.data);
    const authData = forge.util.encode64(serverInfo.user+':'+b64passwd);

    return {
      host: serverInfo.host,
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Authorization': ' Basic '+authData,
        'Date': dateStr,
        'Accept-Encoding': 'gzip'
      },
      abortOnError: true
    };
}

const callServer = function(options, proc) {
    const stime = Date.now();
    const body = options.reqBody;
    if (options.headers === undefined) options.headers = {};
    if (body) options.headers['Content-Length']=`${body.length}`;
    const ctx = options.ctx||{};
    ctx.options = options;
    ctx.times = {start:stime};

    let scheme = https;
    if (options.scheme === 'http') scheme = http;

    if (options.agentOptions) {
        options.agent = new scheme.Agent(options.agentOptions);
    }

    let request = scheme.request(options, (res) => {
        const hdrTime = Date.now();
        ctx._res = res;
        ctx.times.header = hdrTime;
        ctx.remoteAddress = res.connection.remoteAddress;
        if (res.statusCode !== 200 && res.statusCode !== 201 && options.abortOnError) {
            console.error(`Did not get an OK from the server, aborting. Code: ${res.statusCode}`);
            console.error(options.path);
            res.resume();
            return;
        }
        let uncomp = null;
        let ce = res.headers['content-encoding'];
//        console.log(`Contenr-Encoding: ${ce}`);
        switch (ce) {
            case 'br':
                uncomp = zlib.createBrotliDecompress();
                break;
            case 'gzip':
                uncomp = zlib.createGunzip();
                break;
        }
        let data = '';
        let len = 0;
// a good tutorial about stream
//  https://www.freecodecamp.org/news/node-js-streams-everything-you-need-to-know-c9141306be93/
        res.on('data', (chunk) => {
            len += chunk.length;
            if (uncomp) uncomp.write(chunk);
            else data += chunk;
        });
        res.on('end', () => {
            if (uncomp) uncomp.end();
            else finalProc();
        });
        if (uncomp) {
            uncomp.on('data', (chunk) => {
                data += chunk;
            });
            uncomp.on('end', finalProc);
        }
        function finalProc() {
            const resTime = Date.now();
            ctx.times.finish = resTime;
            ctx.bodyBytes={raw:len, decoded:data.length};
            if (options.quiet !== true) {
                const headerSec = (hdrTime - stime)/1000;
                const totalSec = (resTime - stime)/1000;
                console.log(`hdrTime ${headerSec}s, total ${totalSec}s, got status ${res.statusCode} w/ ${len} => ${data.length} bytes from `+ options.host+options.path);
            }
            let ct = res.headers['content-type'] || '';
            if (ct.indexOf('application/json') > -1) {
                proc(JSON.parse(data), ctx);
            }else if (ct.indexOf('application/xml') > -1) {
                xmlParser.parseString(data, (err, obj)=>{proc(obj, ctx)});
            }else proc(data, ctx);
        }
    });

    if (body) request.write(body); //for POST
    request.end();

    request.on('error', (err) => {
        console.error(`Encountered an error trying to make a request: ${err.message}`);
        if (options.abortOnError !== true) {
            const resTime = Date.now();
            ctx.times.finish = resTime;
            ctx.err = err;
            proc(null, ctx);
        }
    });
}

exports.buildAuth = buildCncAuth;
exports.callServer = callServer; 