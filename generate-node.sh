#!/bin/bash

export node_ip=127.0.0.1
export handoff_port=""
export http_port=""
export pb_port=""
export snmp_port=""
export ring_creation_size=""

while [ "${1:0:1}" = "-" -a "${#1}" -gt 1 ]; do
 case ${1:1} in
       p)
	shift
	pb_port="$1"
	shift
	;;
       h)
	shift
	http_port="$1"
	shift
	;;
       d)
	shift
	handoff_port="$1"
	shift
	;;
       s)
	shift
	snmp_port="$1"
	shift
	;;
       n)
	shift
	node_ip=$1
	shift
	;;
       b)
	shift
	backend="$1"
	shift
	;;
       *)
	echo "Unknown option $1"
	exit
 esac
done

if [ ! "$#" -eq 2 ]; then
    echo "Usage: $( basename $0 ) [options] /path/to/bin/riak dest_dir"
    echo -e " Options:\n  -n <node IP address>\n  -h <http_port>\n  -p <pb port>\n  -d <handoff port> -s <snmp_port>"
    echo "      Default IP address is 127.0.0.1, unspecified ports will be chosen randomly"
    exit
fi

CWD="$( cd -P "$( dirname "$0" )" && pwd )"

export src_riak_script="$1"
export src_riak_root="$( cd -P "$( dirname "$1" )" && pwd )"
export src_riak_admin_script="$src_riak_root/riak-admin"
export src_riak_search_cmd="$src_riak_root/search-cmd"

failmsg=""

[ -f $src_riak_script -a -x $src_riak_script ] || failmsg="$failmsg$src_riak_script does not exist or is not executable.\n"
[ -f $src_riak_admin_script -a -x $src_riak_admin_script ] || failmsg="$failmsg$src_riak_admin_script does not exist or is not executable.\n"
[ -f $src_riak_search_cmd -a -x $src_riak_search_cmd ] || failmsg="$failmsg$src_riak_search_cmd does not exist or is not executable.\n"

if [ ! -f $CWD/gen-conf-app.default ]; then
  # Write app.config
  cat - > gen-conf-app.default << EOF
  appconfig_default="
  [
  {riak_core, [
   {ring_state_dir, \"\$data_dir/ring\"},
   {http, [ {\"\$node_ip\", \$http_port } ]},
   {handoff_port, \$handoff_port},
   {platform_bin_dir, \"\$bin_dir\"},
   {platform_data_dir, \"\$data_dir\"},
   {platform_etc_dir, \"\$etc_dir\"},
   {platform_log_dir, \"\$log_dir\"}
  ]},
  {riak_kv, [
   {storage_backend, \$backend},
   {ring_creation_size, \$ring_creation_size},
   {pb_ip, \"\$node_ip\"},
   {pb_port, \$pb_port},
   {mapred_system, pipe},
   {map_js_vm_count, 8},
   {reduce_js_vm_count, 6},
   {hook_js_vm_count, 2},
   {http_url_encoding, on},
   {riak_kv_stat, true},
   {legacy_stats, true},
   {vnode_vclocks, true},
   {legacy_keylisting, false}
  ]},
  {riak_search, [
   {enabled, false}
  ]},
  {merge_index, [
   {data_root, \"\$data_dir/merge_index\"},
   {buffer_rollover_size, 1048576},
   {max_compact_segments, 20}
  ]},
  {bitcask, [
   {data_root, \"\$data_dir/bitcask\"}
  ]},
  {eleveldb, [
   {data_root, \"\$data_dir/leveldb\"}
  ]},
  {luwak, [
   {enabled, false}
  ]},
  {lager, [
   {handlers, [
    {lager_console_backend, info},
    {lager_file_backend, [
     {\"\$log_dir/error.log\", error, 10485760, \"\\\$D0\", 5},
     {\"\$log_dir/console.log\", info, 10485760, \"\\\$D0\", 5}
    ]}
   ]}
  ]},
  {riak_sysmon, [
   {process_limit, 30},
   {port_limit, 2},
   {gc_ms_limit, 100},
   {heap_word_limit, 40111000},
   {busy_port, true},
   {busy_dist_port, true}
  ]},
  {sasl, [
   {sasl_error_logger, false}
  ]}
  ].
  "
EOF
 [ $? = 0 ] || failmsg="${failmsg}Failed to create $CWD/gen-conf-app.default defaults for app.config\n"
fi  

if [ ! -f $CWD/gen-conf-vm.default ]; then
  # Write vm.args 
 cat - > $CWD/gen-conf-vm.default <<EOF
vmargs_default="
-name \$node_name
-setcookie riak
+K true
+A 64
+W w
-env ERL_MAX_PORTS 4096
-env ERL_FULLSWEEP_AFTER 0
-env ERL_CRASH_DUMP \$log_dir/erl_crash.dump
"
EOF
 [ $? = 0 ] || failmsg="${failmsg}Failed to create $CWD/gen-conf-vm.default defaults for vm.args\n"
fi 

if [ -n "$failmsg" ]; then
 echo -e "ERROR:\n$failmsg" >&2
 exit -1
fi

dest_dir="$( dirname "$2/foo" )"
mkdir -p "$dest_dir"
dest_dir="$( cd -P $dest_dir && pwd)"

export bin_dir="$dest_dir/bin"
export etc_dir="$dest_dir/etc"
export log_dir="$dest_dir/log"
export pipe_dir="$dest_dir/tmp/pipe/"
export data_dir="$dest_dir/data"
export ring_dir="$data_dir/ring"
export snmp_dir="$data_dir/snmp"
export riak_script="$bin_dir/riak"
export riak_admin_script="$bin_dir/riak-admin"
export riak_search_cmd="$bin_dir/search-cmd"
export node_name="$( basename $dest_dir )@$node_ip"
export vm_args="$etc_dir/vm.args"
export app_config="$etc_dir/app.config"
export http_port=${http_port:-$((9000 + $(($RANDOM % 100))))}
export pb_port=${pb_port:-$((9100 + $(($RANDOM % 100))))}
export handoff_port=${handoff_port:-$((9200 + $(($RANDOM % 100))))}
export snmp_port=${snmp_port:-$((4000 + $(($RANDOM % 100))))}
export ring_creation_size=${ring_creation_size:-64}
export backend=${backend:-riak_kv_bitcask_backend}

mkdir -p "$bin_dir"
mkdir -p "$etc_dir"
mkdir -p "$log_dir"
mkdir -p "$data_dir"
mkdir -p "$ring_dir"
mkdir -p "$pipe_dir"

cp "$src_riak_script" "$riak_script"
cp "$src_riak_admin_script" "$riak_admin_script"
cp "$src_riak_search_cmd" "$riak_search_cmd"
[ -d "${src_riak_root%/*}"/data/snmp ] && cp -r "${src_riak_root%/*}"/data/snmp "$snmp_dir"
if [ -d "${src_riak_root%/*}"/etc/snmp ]; then
  cp -r "${src_riak_root%/*}"/etc/snmp "$etc_dir"
  sed -i "" -e "s/\({intAgentUDPPort, \)[0-9]*\( }.\)/\1${snmp_port}\2/" $etc_dir/snmp/agent/conf/agent.conf
fi
# Update riak and riak-admin
for script in $riak_script $riak_admin_script $riak_search_cmd; do
    sed -i "" -e "s/^\(RUNNER_SCRIPT_DIR=\)\(.*\)/\1$(echo $bin_dir|sed -e 's/[\/&]/\\&/g')/" $script
    sed -i "" -e "s/^\(RUNNER_ETC_DIR=\)\(.*\)/\1$(echo $etc_dir|sed -e 's/[\/&]/\\&/g')/" $script
    sed -i "" -e "s/^\(RUNNER_USER=\)\(.*\)/\1/" $script
    sed -i "" -e "s/^\(RUNNER_LOG_DIR=\)\(.*\)/\1$(echo $log_dir|sed -e 's/[\/&]/\\&/g')/" $script
    sed -i "" -e "s/^\(PIPE_DIR=\)\(.*\)/\1$(echo $pipe_dir|sed -e 's/[\/&]/\\&/g')/" $script
    sed -i "" -e "s/^\(PLATFORM_DATA_DIR=\)\(.*\)/\1$(echo $data_dir|sed -e 's/[\/&]/\\&/g')/" $script
    sed -i "" -e 's/\(grep "$RUNNER_BASE_DIR\/.*\/\[b\]eam"\)/grep "$RUNNER_ETC_DIR\/app.config"/' $script
    sed -i "" -e "s/^\(RUNNER_BASE_DIR=\)\(\${RUNNER_SCRIPT_DIR%\/\*}\)/\1$(echo ${src_riak_root%/*}|sed -e 's/[\/&]/\\&/g')/" $script
    sed -i "" -e "s/^\(RUNNER_LIB_DIR=\)\(\.\/lib\)/\1$(echo ${src_riak_root%/*}/lib|sed -e 's/[\/&]/\\&/g')/" $script
    sed -i "" -e "s/^\(cd \$RUNNER_BASE_DIR\)/cd $(echo $dest_dir|sed -e 's/[\/&]/\\&/g')/" $script
done

source $CWD/gen-conf-app.default
echo "$appconfig_default" | ${src_riak_root%/*}/erts*/bin/erl -noshell -eval 'Update_item = fun(Newconf, Key, I) when is_list(Newconf) -> Newitem = lists:keyfind(Key, 1, Newconf), if is_tuple(Newitem) -> Newitem; true -> {Key, I} end; (_Newconf, Key, I) -> { Key, I} end, Update_area = fun(Newconf, Area, L) when is_list(L) -> Newarea = lists:keyfind(Area,1,Newconf), if element(2,Newarea) == [<<"-!gen-conf-tombstone!-">>] -> Newarea; is_tuple(Newarea) -> {Area, lists:map(fun({K,D}) -> Update_item(element(2,Newarea), K, D) end, L) }; true -> {Area, L} end; (_Newconf, Area, L) -> {Area, L} end, Update_config = fun([Fnamein,Fnameout]) -> {ok, Newconf} = io:read(""), {ok, [Confin]} = file:consult(Fnamein), Updated_conf = lists:map(fun({Key, L}) ->  Update_area(Newconf, Key, L) end, Confin), {ok, S} = file:open(Fnameout,write), io:format(S, "~p.~n",[lists:filter(fun(X) -> element(2,X) /= [<<"-!gen-conf-tombstone!-">>] end,Updated_conf)]), file:close(S) end, Update_config(["'$src_riak_root'/../etc/app.config", "'$app_config'"]).' -eval "init:stop()." || echo "Failed to update app.config" >&2

sed -E -i '' -e 's/"\.\/(data|bin|etc|log|tmp)/"'$( echo $dest_dir | sed -e 's/\//\\\//g')'\/\1/g' $app_config
sed -E -i "" -e "s/\.\/(lib|erts[^\/]*|lib|releases)/$(echo ${src_riak_root%/*}|sed -e 's/[\/&]/\\&/g')\/\1/g" $app_config
source $CWD/gen-conf-vm.default

echo "$vmargs_default" > $vm_args
