// server.js (unchanged, mas incluído novamente para contexto)
const fs      = require('fs')
const current = GetCurrentResourceName()

function isAuth() { return GetInvokingResource() === current }

exports('readDir', dir => {
    if (!isAuth()) return false;
    try { return fs.readdirSync(dir); }
    catch { return false; }
});

exports('isDir', path => {
    if (!isAuth()) return false;
    try { return fs.lstatSync(path).isDirectory(); }
    catch { return false; }
});

exports('getFileMTime', path => {
    if (!isAuth()) return 0;
    try {
        const stat = fs.statSync(path);
        return stat.mtimeMs || 0;
    } catch {
        return 0;
    }
});
