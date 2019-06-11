package = 'nginx-graphite'
version = 'scm-1'

source  = {
    url    = 'git+https://github.com/moonlibs/nginx-graphite';
    branch = 'master';
}

description = {
    summary  = 'Nginx graphite module';
    homepage = 'git@github.com:moonlibs/nginx-graphite.git';
    license  = 'BSD';
}

dependencies = {
    'lua >= 5.1';
}
build = {
    type = 'builtin';
    modules = {
        ['nginx.socket']   = 'app/socket.lua';
        ['nginx.graphite'] = 'app/graphite.lua';
    };
}

-- vim: syntax=lua
