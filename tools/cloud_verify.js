// 双云本地连接验证脚本（缤纷云 S3 + 坚果云 WebDAV）
// 凭据一律走环境变量，本脚本不含任何密钥，可安全入库。
//
// 用法（PowerShell，把值换成你自己的）：
//   $env:LH_S3_AK='<AccessKey>'; $env:LH_S3_SK='<SecretKey>'; $env:LH_S3_BUCKET='qoderwork'
//   $env:LH_WD_USER='你的邮箱'; $env:LH_WD_PASS='坚果云应用密码'
//   node tools/cloud_verify.js
//
// 输出判读：
//   S3 五个探针若「V2 虚拟主机式」400 而「V1/路径式」200 → App 需换探针口径（把结果发回来）；
//   五个全 4xx → 桶名/子账户桶权限问题（缤纷云控制台→子账户→分配桶权限）；
//   WebDAV 链 PROPFIND(404或207)→MKCOL→PUT→LIST→DELETE 全绿 → 坚果云同步链路通。
'use strict';
const crypto = require('crypto');
const https = require('https');

const S3_AK = process.env.LH_S3_AK || '';
const S3_SK = process.env.LH_S3_SK || '';
const S3_BUCKET = process.env.LH_S3_BUCKET || 'qoderwork';
const S3_HOST = 's3.bitiful.net';
const S3_REGION = 'cn-east-1';
const WD_USER = process.env.LH_WD_USER || '';
const WD_PASS = process.env.LH_WD_PASS || '';
const WD_DIR = 'qoderwork'; // 云端目录名（与 App 内配置一致）

if (!S3_AK || !S3_SK || !WD_USER || !WD_PASS) {
  console.error('缺少环境变量 LH_S3_AK/LH_S3_SK/LH_WD_USER/LH_WD_PASS');
  process.exit(2);
}
const EMPTY_SHA = crypto.createHash('sha256').update('').digest('hex');
const pad = (n) => String(n).padStart(2, '0');

function s3Req({ host, path, query = '', method = 'GET', region = S3_REGION, body = null }) {
  const d = new Date();
  const amzDate = `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
  const dateStamp = amzDate.slice(0, 8);
  const payloadHash = body ? crypto.createHash('sha256').update(body).digest('hex') : EMPTY_SHA;
  const ch = `host:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const sh = 'host;x-amz-content-sha256;x-amz-date';
  const cr = `${method}\n${path}\n${query}\n${ch}\n${sh}\n${payloadHash}`;
  const scope = `${dateStamp}/${region}/s3/aws4_request`;
  const sts = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n` + crypto.createHash('sha256').update(cr).digest('hex');
  const hm = (k, s) => crypto.createHmac('sha256', k).update(s, 'utf8').digest();
  const key = hm(hm(hm(hm('AWS4' + S3_SK, dateStamp), region), 's3'), 'aws4_request');
  const sig = crypto.createHmac('sha256', key).update(sts).digest('hex');
  return raw({
    host, path: query ? `${path}?${query}` : path, method, body,
    headers: {
      host, 'x-amz-date': amzDate, 'x-amz-content-sha256': payloadHash,
      authorization: `AWS4-HMAC-SHA256 Credential=${S3_AK}/${scope}, SignedHeaders=${sh}, Signature=${sig}`,
    },
  });
}

function wdReq({ method, path, body = null, depth = null, extraHeaders = {} }) {
  const auth = Buffer.from(WD_USER + ':' + WD_PASS).toString('base64');
  const headers = { host: 'dav.jianguoyun.com', authorization: 'Basic ' + auth, ...extraHeaders };
  if (depth) headers['Depth'] = depth;
  if (body) headers['Content-Type'] = 'application/xml';
  return raw({ host: 'dav.jianguoyun.com', path, method, body, headers });
}

function raw({ host, path, method, headers, body = null }) {
  return new Promise((resolve) => {
    const req = https.request({ host, path, method, headers }, (r) => {
      let b = '';
      r.on('data', (c) => (b += c));
      r.on('end', () => resolve({ status: r.statusCode, body: b.slice(0, 300) }));
    });
    req.on('error', (e) => resolve({ err: e.message }));
    if (body) req.write(body);
    req.end();
  });
}

const code = (r) => (r.err ? `ERR ${r.err}` : `${r.status} ${(r.body.match(/<Code>([^<]+)<\/Code>/) || [])[1] || ''}`);

(async () => {
  console.log('=== 缤纷云 S3（App 同款签名，五探针对照）===');
  console.log('1 V2 虚拟主机式(App 当前探针) :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/', query: 'list-type=2&max-keys=1' })));
  console.log('2 V1 虚拟主机式              :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/', query: 'max-keys=1' })));
  console.log('3 V2 路径式                  :', code(await s3Req({ host: S3_HOST, path: `/${S3_BUCKET}/`, query: 'list-type=2&max-keys=1' })));
  console.log('4 HEAD 桶存在性              :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/', method: 'HEAD' })));
  console.log('5 根端点列桶(子账户预期403)  :', code(await s3Req({ host: S3_HOST, path: '/' })));
  const put = await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/lh_probe.tmp', method: 'PUT', body: 'probe' });
  console.log('6 PUT 小探针文件             :', code(put));
  if (put.status === 200) {
    console.log('7 DELETE 清理                :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/lh_probe.tmp', method: 'DELETE' })));
  }

  console.log('\n=== 坚果云 WebDAV（App 同步链路复演）===');
  const P = `/dav/${WD_DIR}/`;
  console.log('1 PROPFIND 目录(404=未建,207=已存在):', code(await wdReq({ method: 'PROPFIND', path: P, depth: '1', body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><getcontentlength xmlns="DAV:"/><getlastmodified xmlns="DAV:"/></d:prop></d:propfind>' })));
  console.log('2 MKCOL 建目录(405=已存在亦成功)   :', code(await wdReq({ method: 'MKCOL', path: P })));
  const up = await wdReq({ method: 'PUT', path: `${P}lh_probe.tmp`, body: 'probe' });
  console.log('3 PUT 探针文件                     :', code(up));
  console.log('4 PROPFIND 应可见探针               :', code(await wdReq({ method: 'PROPFIND', path: P, depth: '1', body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>' })));
  if (up.status === 201 || up.status === 204 || up.status === 200) {
    console.log('5 DELETE 清理                      :', code(await wdReq({ method: 'DELETE', path: `${P}lh_probe.tmp` })));
  }
  console.log('\n把以上输出整段发回来即可判定。');
})();
