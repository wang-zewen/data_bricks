const express = require("express");
const app = express();
const axios = require("axios");
const os = require('os');
const fs = require("fs");
const path = require("path");
const { promisify } = require('util');
const exec = promisify(require('child_process').exec);
const { execSync } = require('child_process');

// ================================
// 配置变量
// ================================
const UPLOAD_URL = process.env.UPLOAD_URL || '';
const PROJECT_URL = process.env.PROJECT_URL || '';
const AUTO_ACCESS = process.env.AUTO_ACCESS || false;
const FILE_PATH = process.env.FILE_PATH || './tmp';
const SUB_PATH = process.env.SUB_PATH || 'sub';
const PORT = process.env.SERVER_PORT || process.env.PORT || 3000;
const UUID = process.env.UUID || '9afd1229-b893-40c1-84dd-51e7ce204913';
const CFIP = process.env.CFIP || 'cdns.doon.eu.org';
const CFPORT = process.env.CFPORT || 443;
const NAME = process.env.NAME || '';

// Xray 配置
const XRAY_PORT = process.env.XRAY_PORT || 8001;
const SOCKS_PORT = process.env.SOCKS_PORT || 1080;

// 隧道配置 (bore.pub 替代 Argo)
const TUNNEL_TYPE = process.env.TUNNEL_TYPE || 'bore';  // bore | ngrok | localtunnel
const BORE_SERVER = process.env.BORE_SERVER || 'bore.pub';
const BORE_PORT = process.env.BORE_PORT || 2200;
const NGROK_TOKEN = process.env.NGROK_TOKEN || '';

// 哪吒监控（可选）
const NEZHA_SERVER = process.env.NEZHA_SERVER || '';
const NEZHA_PORT = process.env.NEZHA_PORT || '';
const NEZHA_KEY = process.env.NEZHA_KEY || '';

// ================================
// 全局变量
// ================================
const generateRandomName = () => {
  const characters = 'abcdefghijklmnopqrstuvwxyz';
  let result = '';
  for (let i = 0; i < 6; i++) {
    result += characters.charAt(Math.floor(Math.random() * characters.length));
  }
  return result;
};

const npmName = generateRandomName();
const webName = generateRandomName();
const tunnelName = generateRandomName();
const phpName = generateRandomName();

let npmPath = path.join(FILE_PATH, npmName);
let phpPath = path.join(FILE_PATH, phpName);
let webPath = path.join(FILE_PATH, webName);
let tunnelPath = path.join(FILE_PATH, tunnelName);
let subPath = path.join(FILE_PATH, 'sub.txt');
let listPath = path.join(FILE_PATH, 'list.txt');
let tunnelLogPath = path.join(FILE_PATH, 'tunnel.log');
let configPath = path.join(FILE_PATH, 'config.json');

// ================================
// 创建工作目录
// ================================
if (!fs.existsSync(FILE_PATH)) {
  fs.mkdirSync(FILE_PATH);
  console.log(`${FILE_PATH} is created`);
} else {
  console.log(`${FILE_PATH} already exists`);
}

// ================================
// 清理历史文件
// ================================
function cleanupOldFiles() {
  try {
    const files = fs.readdirSync(FILE_PATH);
    files.forEach(file => {
      const filePath = path.join(FILE_PATH, file);
      try {
        const stat = fs.statSync(filePath);
        if (stat.isFile()) {
          fs.unlinkSync(filePath);
        }
      } catch (err) {
        // 忽略错误
      }
    });
  } catch (err) {
    // 忽略错误
  }
}

// ================================
// 删除历史节点
// ================================
function deleteNodes() {
  try {
    if (!UPLOAD_URL) return;
    if (!fs.existsSync(subPath)) return;

    let fileContent;
    try {
      fileContent = fs.readFileSync(subPath, 'utf-8');
    } catch {
      return null;
    }

    const decoded = Buffer.from(fileContent, 'base64').toString('utf-8');
    const nodes = decoded.split('\n').filter(line =>
      /(vless|vmess|trojan|hysteria2|tuic):\/\//.test(line)
    );

    if (nodes.length === 0) return;

    axios.post(`${UPLOAD_URL}/api/delete-nodes`,
      JSON.stringify({ nodes }),
      { headers: { 'Content-Type': 'application/json' } }
    ).catch(() => null);
    return null;
  } catch (err) {
    return null;
  }
}

// ================================
// 根路由
// ================================
app.get("/", function(req, res) {
  res.send("Hello world! Xray with bore.pub tunnel is running.");
});

// ================================
// 生成 Xray 配置文件
// ================================
async function generateConfig() {
  const config = {
    log: { access: '/dev/null', error: '/dev/null', loglevel: 'none' },
    inbounds: [
      {
        port: XRAY_PORT,
        protocol: 'vless',
        settings: {
          clients: [{ id: UUID, flow: 'xtls-rprx-vision' }],
          decryption: 'none',
          fallbacks: [
            { dest: 3001 },
            { path: "/vless", dest: 3002 },
            { path: "/vmess", dest: 3003 },
            { path: "/trojan", dest: 3004 }
          ]
        },
        streamSettings: { network: 'tcp' }
      },
      {
        port: 3001,
        listen: "127.0.0.1",
        protocol: "vless",
        settings: { clients: [{ id: UUID }], decryption: "none" },
        streamSettings: { network: "tcp", security: "none" }
      },
      {
        port: 3002,
        listen: "127.0.0.1",
        protocol: "vless",
        settings: { clients: [{ id: UUID, level: 0 }], decryption: "none" },
        streamSettings: { network: "ws", security: "none", wsSettings: { path: "/vless" } },
        sniffing: { enabled: true, destOverride: ["http", "tls", "quic"], metadataOnly: false }
      },
      {
        port: 3003,
        listen: "127.0.0.1",
        protocol: "vmess",
        settings: { clients: [{ id: UUID, alterId: 0 }] },
        streamSettings: { network: "ws", wsSettings: { path: "/vmess" } },
        sniffing: { enabled: true, destOverride: ["http", "tls", "quic"], metadataOnly: false }
      },
      {
        port: 3004,
        listen: "127.0.0.1",
        protocol: "trojan",
        settings: { clients: [{ password: UUID }] },
        streamSettings: { network: "ws", security: "none", wsSettings: { path: "/trojan" } },
        sniffing: { enabled: true, destOverride: ["http", "tls", "quic"], metadataOnly: false }
      },
      {
        port: SOCKS_PORT,
        listen: "0.0.0.0",
        protocol: "socks",
        settings: { auth: "noauth", udp: true }
      }
    ],
    dns: { servers: ["https+local://8.8.8.8/dns-query"] },
    outbounds: [
      { protocol: "freedom", tag: "direct" },
      { protocol: "blackhole", tag: "block" }
    ]
  };
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

// ================================
// 检测系统架构
// ================================
function getSystemArchitecture() {
  const arch = os.arch();
  if (arch === 'arm' || arch === 'arm64' || arch === 'aarch64') {
    return 'arm';
  } else {
    return 'amd';
  }
}

// ================================
// 下载文件
// ================================
function downloadFile(fileName, fileUrl, callback) {
  const filePath = fileName;

  if (!fs.existsSync(FILE_PATH)) {
    fs.mkdirSync(FILE_PATH, { recursive: true });
  }

  const writer = fs.createWriteStream(filePath);

  axios({
    method: 'get',
    url: fileUrl,
    responseType: 'stream',
  })
    .then(response => {
      response.data.pipe(writer);

      writer.on('finish', () => {
        writer.close();
        console.log(`Download ${path.basename(filePath)} successfully`);
        callback(null, filePath);
      });

      writer.on('error', err => {
        fs.unlink(filePath, () => {});
        const errorMessage = `Download ${path.basename(filePath)} failed: ${err.message}`;
        console.error(errorMessage);
        callback(errorMessage);
      });
    })
    .catch(err => {
      const errorMessage = `Download ${path.basename(filePath)} failed: ${err.message}`;
      console.error(errorMessage);
      callback(errorMessage);
    });
}

// ================================
// 获取下载文件列表
// ================================
function getFilesForArchitecture(architecture) {
  let baseFiles;
  if (architecture === 'arm') {
    baseFiles = [
      { fileName: webPath, fileUrl: "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip" }
    ];
  } else {
    baseFiles = [
      { fileName: webPath, fileUrl: "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" }
    ];
  }

  // 添加bore或其他tunnel
  if (TUNNEL_TYPE === 'bore') {
    const boreUrl = architecture === 'arm'
      ? "https://github.com/ekzhang/bore/releases/download/v0.5.0/bore-v0.5.0-aarch64-unknown-linux-musl.tar.gz"
      : "https://github.com/ekzhang/bore/releases/download/v0.5.0/bore-v0.5.0-x86_64-unknown-linux-musl.tar.gz";
    baseFiles.push({ fileName: tunnelPath + '.tar.gz', fileUrl: boreUrl });
  } else if (TUNNEL_TYPE === 'ngrok') {
    const ngrokUrl = architecture === 'arm'
      ? "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz"
      : "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
    baseFiles.push({ fileName: tunnelPath + '.tgz', fileUrl: ngrokUrl });
  }

  // 添加哪吒监控（如果配置）
  if (NEZHA_SERVER && NEZHA_KEY) {
    if (NEZHA_PORT) {
      const npmUrl = architecture === 'arm'
        ? "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_arm64.zip"
        : "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_amd64.zip";
      baseFiles.unshift({ fileName: npmPath + '.zip', fileUrl: npmUrl });
    } else {
      const phpUrl = architecture === 'arm'
        ? "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_arm64.zip"
        : "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_amd64.zip";
      baseFiles.unshift({ fileName: phpPath + '.zip', fileUrl: phpUrl });
    }
  }

  return baseFiles;
}

// ================================
// 下载并运行
// ================================
async function downloadFilesAndRun() {
  const architecture = getSystemArchitecture();
  const filesToDownload = getFilesForArchitecture(architecture);

  if (filesToDownload.length === 0) {
    console.log(`Can't find files for the current architecture`);
    return;
  }

  const downloadPromises = filesToDownload.map(fileInfo => {
    return new Promise((resolve, reject) => {
      downloadFile(fileInfo.fileName, fileInfo.fileUrl, (err, filePath) => {
        if (err) {
          reject(err);
        } else {
          resolve(filePath);
        }
      });
    });
  });

  try {
    await Promise.all(downloadPromises);
  } catch (err) {
    console.error('Error downloading files:', err);
    return;
  }

  // 解压文件
  try {
    // 解压 Xray
    if (fs.existsSync(webPath)) {
      await exec(`cd ${FILE_PATH} && unzip -q ${webName} && chmod +x xray`);
      webPath = path.join(FILE_PATH, 'xray');
      console.log('Xray extracted successfully');
    }

    // 解压tunnel
    if (TUNNEL_TYPE === 'bore' && fs.existsSync(tunnelPath + '.tar.gz')) {
      await exec(`cd ${FILE_PATH} && tar -xzf ${tunnelName}.tar.gz && chmod +x bore`);
      tunnelPath = path.join(FILE_PATH, 'bore');
      console.log('Bore extracted successfully');
    } else if (TUNNEL_TYPE === 'ngrok' && fs.existsSync(tunnelPath + '.tgz')) {
      await exec(`cd ${FILE_PATH} && tar -xzf ${tunnelName}.tgz && chmod +x ngrok`);
      tunnelPath = path.join(FILE_PATH, 'ngrok');
      console.log('Ngrok extracted successfully');
    }

    // 解压哪吒
    if (NEZHA_SERVER && NEZHA_KEY) {
      if (NEZHA_PORT && fs.existsSync(npmPath + '.zip')) {
        await exec(`cd ${FILE_PATH} && unzip -q ${npmName}.zip && chmod +x nezha-agent`);
        npmPath = path.join(FILE_PATH, 'nezha-agent');
      } else if (fs.existsSync(phpPath + '.zip')) {
        await exec(`cd ${FILE_PATH} && unzip -q ${phpName}.zip && chmod +x nezha-agent`);
        phpPath = path.join(FILE_PATH, 'nezha-agent');
      }
    }
  } catch (error) {
    console.error('Error extracting files:', error);
  }

  // 运行哪吒监控
  if (NEZHA_SERVER && NEZHA_KEY) {
    if (!NEZHA_PORT) {
      const port = NEZHA_SERVER.includes(':') ? NEZHA_SERVER.split(':').pop() : '';
      const tlsPorts = new Set(['443', '8443', '2096', '2087', '2083', '2053']);
      const nezhatls = tlsPorts.has(port) ? 'true' : 'false';

      const configYaml = `
client_secret: ${NEZHA_KEY}
debug: false
disable_auto_update: true
disable_command_execute: false
disable_force_update: true
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: true
ip_report_period: 1800
report_delay: 4
server: ${NEZHA_SERVER}
skip_connection_count: true
skip_procs_count: true
temperature: false
tls: ${nezhatls}
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: ${UUID}`;

      fs.writeFileSync(path.join(FILE_PATH, 'config.yaml'), configYaml);

      const command = `nohup ${phpPath} -c "${FILE_PATH}/config.yaml" >/dev/null 2>&1 &`;
      try {
        await exec(command);
        console.log(`Nezha is running`);
        await new Promise((resolve) => setTimeout(resolve, 1000));
      } catch (error) {
        console.error(`Nezha running error: ${error}`);
      }
    } else {
      let NEZHA_TLS = '';
      const tlsPorts = ['443', '8443', '2096', '2087', '2083', '2053'];
      if (tlsPorts.includes(NEZHA_PORT)) {
        NEZHA_TLS = '--tls';
      }
      const command = `nohup ${npmPath} -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} --disable-auto-update --report-delay 4 --skip-conn --skip-procs >/dev/null 2>&1 &`;
      try {
        await exec(command);
        console.log(`Nezha is running`);
        await new Promise((resolve) => setTimeout(resolve, 1000));
      } catch (error) {
        console.error(`Nezha running error: ${error}`);
      }
    }
  }

  // 运行 Xray
  const xrayCommand = `nohup ${webPath} -c ${configPath} >/dev/null 2>&1 &`;
  try {
    await exec(xrayCommand);
    console.log(`Xray is running on port ${XRAY_PORT}`);
    await new Promise((resolve) => setTimeout(resolve, 1000));
  } catch (error) {
    console.error(`Xray running error: ${error}`);
  }

  // 运行隧道
  if (TUNNEL_TYPE === 'bore') {
    const boreCommand = `nohup ${tunnelPath} local ${XRAY_PORT} --to ${BORE_SERVER} --port ${BORE_PORT} > ${tunnelLogPath} 2>&1 &`;
    try {
      await exec(boreCommand);
      console.log(`Bore tunnel is running`);
      await new Promise((resolve) => setTimeout(resolve, 3000));
    } catch (error) {
      console.error(`Bore error: ${error}`);
    }
  } else if (TUNNEL_TYPE === 'ngrok') {
    if (!NGROK_TOKEN) {
      console.error('NGROK_TOKEN is required for ngrok');
    } else {
      await exec(`${tunnelPath} authtoken ${NGROK_TOKEN}`);
      const ngrokCommand = `nohup ${tunnelPath} http ${XRAY_PORT} --log=stdout > ${tunnelLogPath} 2>&1 &`;
      try {
        await exec(ngrokCommand);
        console.log(`Ngrok tunnel is running`);
        await new Promise((resolve) => setTimeout(resolve, 3000));
      } catch (error) {
        console.error(`Ngrok error: ${error}`);
      }
    }
  }

  await new Promise((resolve) => setTimeout(resolve, 5000));
}

// ================================
// 获取隧道域名
// ================================
async function extractDomains() {
  let tunnelDomain;
  let tunnelPort = CFPORT;

  try {
    const fileContent = fs.readFileSync(tunnelLogPath, 'utf-8');

    if (TUNNEL_TYPE === 'bore') {
      // bore 格式: listening at bore.pub:xxxxx
      const match = fileContent.match(/listening at ([^\s]+)/);
      if (match) {
        const addr = match[1];
        if (addr.includes(':')) {
          tunnelDomain = addr.split(':')[0];
          tunnelPort = addr.split(':')[1];
        } else {
          tunnelDomain = addr;
        }
      }
    } else if (TUNNEL_TYPE === 'ngrok') {
      // ngrok 需要从API获取
      try {
        const response = await axios.get('http://localhost:4040/api/tunnels');
        if (response.data && response.data.tunnels && response.data.tunnels[0]) {
          const url = response.data.tunnels[0].public_url;
          tunnelDomain = url.replace('https://', '').replace('http://', '');
          tunnelPort = 443;
        }
      } catch (err) {
        console.error('Failed to get ngrok domain from API');
      }
    }

    if (tunnelDomain) {
      console.log('Tunnel Domain:', tunnelDomain);
      console.log('Tunnel Port:', tunnelPort);
      await generateLinks(tunnelDomain, tunnelPort);
    } else {
      console.log('Tunnel domain not found');
      // 重试
      await new Promise((resolve) => setTimeout(resolve, 3000));
      await extractDomains();
    }
  } catch (error) {
    console.error('Error reading tunnel log:', error);
    // 重试
    await new Promise((resolve) => setTimeout(resolve, 3000));
    await extractDomains();
  }
}

// ================================
// 生成订阅链接
// ================================
async function generateLinks(tunnelDomain, tunnelPort) {
  const metaInfo = execSync(
    'curl -sm 5 https://speed.cloudflare.com/meta | awk -F\\" \'{print $26"-"$18}\' | sed -e \'s/ /_/g\'',
    { encoding: 'utf-8' }
  );
  const ISP = metaInfo.trim();
  const nodeName = NAME ? `${NAME}-${ISP}` : ISP;

  return new Promise((resolve) => {
    setTimeout(() => {
      const VMESS = {
        v: '2',
        ps: `${nodeName}`,
        add: CFIP,
        port: CFPORT,
        id: UUID,
        aid: '0',
        scy: 'none',
        net: 'ws',
        type: 'none',
        host: tunnelDomain,
        path: '/vmess?ed=2560',
        tls: 'tls',
        sni: tunnelDomain,
        alpn: '',
        fp: 'firefox'
      };

      const subTxt = `
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${tunnelDomain}&fp=firefox&type=ws&host=${tunnelDomain}&path=%2Fvless%3Fed%3D2560#${nodeName}

vmess://${Buffer.from(JSON.stringify(VMESS)).toString('base64')}

trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${tunnelDomain}&fp=firefox&type=ws&host=${tunnelDomain}&path=%2Ftrojan%3Fed%3D2560#${nodeName}
      `;

      console.log(Buffer.from(subTxt).toString('base64'));
      fs.writeFileSync(subPath, Buffer.from(subTxt).toString('base64'));
      console.log(`${subPath} saved successfully`);
      uploadNodes();

      app.get(`/${SUB_PATH}`, (req, res) => {
        const encodedContent = Buffer.from(subTxt).toString('base64');
        res.set('Content-Type', 'text/plain; charset=utf-8');
        res.send(encodedContent);
      });

      resolve(subTxt);
    }, 2000);
  });
}

// ================================
// 上传节点/订阅
// ================================
async function uploadNodes() {
  if (UPLOAD_URL && PROJECT_URL) {
    const subscriptionUrl = `${PROJECT_URL}/${SUB_PATH}`;
    const jsonData = { subscription: [subscriptionUrl] };

    try {
      const response = await axios.post(`${UPLOAD_URL}/api/add-subscriptions`, jsonData, {
        headers: { 'Content-Type': 'application/json' }
      });

      if (response && response.status === 200) {
        console.log('Subscription uploaded successfully');
        return response;
      }
    } catch (error) {
      // 忽略错误
    }
  } else if (UPLOAD_URL) {
    if (!fs.existsSync(listPath)) return;
    const content = fs.readFileSync(listPath, 'utf-8');
    const nodes = content.split('\n').filter(line => /(vless|vmess|trojan|hysteria2|tuic):\/\//.test(line));

    if (nodes.length === 0) return;

    const jsonData = JSON.stringify({ nodes });

    try {
      const response = await axios.post(`${UPLOAD_URL}/api/add-nodes`, jsonData, {
        headers: { 'Content-Type': 'application/json' }
      });
      if (response && response.status === 200) {
        console.log('Nodes uploaded successfully');
        return response;
      }
    } catch (error) {
      // 忽略错误
    }
  }
}

// ================================
// 清理文件
// ================================
function cleanFiles() {
  setTimeout(() => {
    const filesToDelete = [tunnelLogPath, configPath, webPath, tunnelPath];

    if (NEZHA_PORT) {
      filesToDelete.push(npmPath);
    } else if (NEZHA_SERVER && NEZHA_KEY) {
      filesToDelete.push(phpPath);
    }

    const deleteCommand = process.platform === 'win32'
      ? `del /f /q ${filesToDelete.join(' ')} > nul 2>&1`
      : `rm -rf ${filesToDelete.join(' ')} >/dev/null 2>&1`;

    exec(deleteCommand, (error) => {
      console.clear();
      console.log('App is running');
      console.log('Thank you for using this script, enjoy!');
    });
  }, 90000);
}
cleanFiles();

// ================================
// 自动访问项目URL
// ================================
async function AddVisitTask() {
  if (!AUTO_ACCESS || !PROJECT_URL) {
    console.log("Skipping adding automatic access task");
    return;
  }

  try {
    const response = await axios.post('https://oooo.serv00.net/add-url', {
      url: PROJECT_URL
    }, {
      headers: { 'Content-Type': 'application/json' }
    });
    console.log(`Automatic access task added successfully`);
    return response;
  } catch (error) {
    console.error(`Add automatic access task failed: ${error.message}`);
    return null;
  }
}

// ================================
// 主函数
// ================================
async function startServer() {
  try {
    deleteNodes();
    cleanupOldFiles();
    await generateConfig();
    await downloadFilesAndRun();
    await extractDomains();
    await AddVisitTask();
  } catch (error) {
    console.error('Error in startServer:', error);
  }
}

startServer().catch(error => {
  console.error('Unhandled error in startServer:', error);
});

app.listen(PORT, () => console.log(`HTTP server is running on port:${PORT}!`));
