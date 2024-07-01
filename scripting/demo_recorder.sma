#include <amxmodx>
#include <reapi>
#include <nvault>

forward fbans_player_banned_pre(const id);

const TASK_DEMO = 32451;
const TASK_CHAT = 32411;

new g_szCallBack[] = "demo_callBack";

enum _: CVARS  {
	DEMONUM,
	DEMONAME[24],
	DEMOPREFIX[24]
}

new pCvar[CVARS];
new _:g_iSettings[CVARS];


new g_iCurrentDemoID[MAX_PLAYERS + 1];
new bool:g_bDemoRecording[MAX_PLAYERS + 1];

new g_iSearch;

new bool:g_bNotDemoFiles[MAX_PLAYERS + 1][10];

new g_iVault;

new g_szLogFile[128];
new const LOG_FILE_NAME[16] = "DemoRecorder"

new g_szChooseFile[64];

public plugin_init() {
	register_plugin("Demo recorder", "1.3.2", "WessTorn");

	register_clcmd("demo_menu", "demoMenu", ADMIN_BAN);

	pCvar[DEMONUM] = create_cvar("demo_num", "5", FCVAR_NONE, "Number of demos provided / Кол-во демо", true, 1.0, true, 10.0);
	bind_pcvar_num(pCvar[DEMONUM], g_iSettings[DEMONUM]);

	pCvar[DEMONAME] = create_cvar("demo_name", "Demo-Name", FCVAR_NONE, "Demo title / Название демо");
	bind_pcvar_string(pCvar[DEMONAME], g_iSettings[DEMONAME], charsmax(g_iSettings[DEMONAME]));

	pCvar[DEMOPREFIX] = create_cvar("demo_prefix", "DEMO", FCVAR_NONE, "Chat prefix / Префикс чата");
	bind_pcvar_string(pCvar[DEMOPREFIX], g_iSettings[DEMOPREFIX], charsmax(g_iSettings[DEMOPREFIX]));

	AutoExecConfig(true, "demo_recorder");

	new szPath[PLATFORM_MAX_PATH]; get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
	server_cmd("exec %s/plugins/demo_recorder.cfg", szPath);
	server_exec();

	register_dictionary("demo_recorder.txt");

	g_iSearch = 7 + strlen(g_iSettings[DEMONAME]) + 2;

	if (g_iSettings[DEMONUM]) {
		for (new i = 1; i <= g_iSettings[DEMONUM]; i++) {
			new szList[64], iLen;
			iLen += format(szList[iLen], sizeof szList - iLen, "cstrike/");
			iLen += format(szList[iLen], sizeof szList - iLen, "%s_%d.dem", g_iSettings[DEMONAME], i);
			RegisterQueryFile(szList, g_szCallBack, RES_TYPE_MISSING)
		}

		RegisterHookChain(RC_FileConsistencyProcess, "FileConsistencyProcess", false);
		server_print("%L", 0, "DEMO_GOOD", g_iSettings[DEMONAME]);
	} else {
		server_print("%L", 0, "DEMO_BAD");
	}

	RegisterHookChain(RG_CBasePlayer_Spawn, "rgPlayerSpawn", true);
	RegisterHookChain(RH_SV_DropClient, "rgDropClient");
	RegisterHookChain(RG_CSGameRules_ServerDeactivate, "rgServerDeactivate");
}

public demoMenu(id) {
	if (!is_user_connected(id)) {
		return PLUGIN_HANDLED;
	}

	if (~get_user_flags(id) & ADMIN_BAN) {
		client_print(id, print_console, "%L", id, "DEMO_ACCESS", g_iSettings[DEMOPREFIX]);
		return PLUGIN_HANDLED;
	}

	new szMsg[64];

	formatex(szMsg, charsmax(szMsg), "%L", id, "DEMO_MENU_TITLE");
	new hMenu = menu_create(szMsg, "demoMenuHandler");

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");

	for (new i; i < iNum; i++) {
		new iPlayer = iPlayers[i];
		
		new szName[32]; get_user_name(iPlayer, szName, charsmax(szName));
		new szPlayer[32]; num_to_str(iPlayer, szPlayer, charsmax(szPlayer));
		
		menu_additem(hMenu, szName, szPlayer, 0);
	}

	formatex(szMsg, charsmax(szMsg), "%L", id, "DEMO_MENU_PLAYER_EXIT");
	menu_setprop(hMenu, MPROP_EXITNAME, szMsg);

	menu_display(id, hMenu, 0);

	return PLUGIN_HANDLED;
}

public demoMenuHandler(id, hMenu, item) {
	if (!is_user_connected(id)) {
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}

	if (item == MENU_EXIT) {
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}

	new szData[6], szName[64], iAccess, iCallback;
	menu_item_getinfo(hMenu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
	menu_destroy(hMenu);
	
	new iPlayer = str_to_num(szData);

	if (!is_user_connected(iPlayer)) {
		demoMenu(id);
		return PLUGIN_HANDLED;
	}

	playerDemoMenu(id, iPlayer);

	return PLUGIN_HANDLED;
}

new g_iPlayer[MAX_PLAYERS + 1];

public playerDemoMenu(id, iPlayer) {
	if (!is_user_connected(id)) {
		return PLUGIN_HANDLED;
	}

	if (!is_user_connected(iPlayer)) {
		client_print_color(id, print_team_blue, "%L", id, "DEMO_NOT_CONNECT", g_iSettings[DEMOPREFIX]);
		return PLUGIN_HANDLED;
	}

	g_iPlayer[id] = iPlayer;

	new szAuthID[32];
	get_user_authid(iPlayer, szAuthID, charsmax(szAuthID));

	new szMsg[64];

	formatex(szMsg, charsmax(szMsg), "%L^n\d%n (%s)", id, "DEMO_MENU_PLAYER_TITLE", iPlayer, szAuthID);
	new hMenu = menu_create(szMsg, "playerDemoMenuHandler");

	formatex(szMsg, charsmax(szMsg), "%L^n", id, "DEMO_MENU_PLAYER_BAN");
	menu_additem(hMenu, szMsg, "1");

	formatex(szMsg, charsmax(szMsg), "%L %s", id, "DEMO_MENU_PLAYER_NAME", g_iSettings[DEMONAME]);
	menu_addtext(hMenu, szMsg, 1);
	
	new szList[132], iLen;
	iLen += format(szList[iLen], sizeof szList - iLen, "%L ", id, "DEMO_MENU_PLAYER_DEMOS");

	for (new i = 0; i < g_iSettings[DEMONUM]; i++) {
		if (i + 1 == g_iCurrentDemoID[id]) {
			iLen += format(szList[iLen], sizeof szList - iLen, "%d(R) ", i + 1);
		} else {
			iLen += format(szList[iLen], sizeof szList - iLen, "%d(%s) ", i + 1, g_bNotDemoFiles[iPlayer][i] ? "-" : "+");
		}
	}

	menu_addtext(hMenu, szList, 1);

	formatex(szMsg, charsmax(szMsg), "%L", id, "DEMO_MENU_PLAYER_BACK");
	menu_setprop(hMenu, MPROP_EXITNAME, szMsg);

	menu_display(id, hMenu, 0);

	return PLUGIN_HANDLED;
}

public playerDemoMenuHandler(id, hMenu, item) {
	if (!is_user_connected(id)) {
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}

	if (item == MENU_EXIT) {
		menu_destroy(hMenu);
		g_iPlayer[id] = 0;
		demoMenu(id);
		return PLUGIN_HANDLED;
	}

	new szData[6], szName[64], iAccess, iCallback;
	menu_item_getinfo(hMenu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
	menu_destroy(hMenu);

	new iKey = str_to_num(szData);

	switch (iKey) {
		case 1: {
			if (is_user_connected(g_iPlayer[id])) {
				verifMenu(id);
			} else {
				client_print_color(id, print_team_blue, "%L", id, "DEMO_NOT_CONNECT", g_iSettings[DEMOPREFIX]);
				demoMenu(id);
			}
		}
	}

	return PLUGIN_HANDLED;
}

public verifMenu(id) {
	if (!is_user_connected(id) || !is_user_connected(g_iPlayer[id]))
		return PLUGIN_HANDLED;

	new szMsg[132];

	formatex(szMsg, charsmax(szMsg), "%L", id, "DEMO_MENU_VERIF_TITLE", g_iPlayer[id]);
	new hMenu = menu_create(szMsg, "verifMenuHandler");

	formatex(szMsg, charsmax(szMsg), "%L", id, "DEMO_MENU_VERIF_NO");
	menu_additem(hMenu, szMsg, "1");

	formatex(szMsg, charsmax(szMsg), "%L", id, "DEMO_MENU_VERIF_YES");
	menu_additem(hMenu, szMsg, "2");

	menu_display(id, hMenu, 0);

	return PLUGIN_HANDLED;
}

public verifMenuHandler(id, hMenu, item) {
	if (!is_user_connected(id) || !is_user_connected(g_iPlayer[id])) {
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}

	if (item == MENU_EXIT) {
		menu_destroy(hMenu);
		return PLUGIN_HANDLED;
	}

	menu_destroy(hMenu);

	switch (item) {
		case 0: {
			demoMenu(id);
			g_iPlayer[id] = 0;
			return PLUGIN_HANDLED;
		}
		case 1: {
			if (is_user_connected(g_iPlayer[id])) {
				server_cmd("fb_ban ^"0^" #%d ^"Check demo^"", get_user_userid(g_iPlayer[id]));
			} else {
				client_print_color(id, print_team_blue, "%L", id, "DEMO_NOT_CONNECT", g_iSettings[DEMOPREFIX]);
				demoMenu(id);
			}
			g_iPlayer[id] = 0;
		}
	}
	
	return PLUGIN_HANDLED;
}


public FileConsistencyProcess(const id, const filename[], const cmd[], const ResourceType:type) {
	if (type == RES_TYPE_MISSING && !cmd[0]) {
		formatex(g_szChooseFile, charsmax(g_szChooseFile), "%s", filename);
	}
}

public demo_callBack(const id) {
	new iNumDemo = str_to_num(g_szChooseFile[g_iSearch]);
	if (iNumDemo != g_iCurrentDemoID[id]) {
		g_bNotDemoFiles[id][iNumDemo - 1] = true;
	}
}

public fbans_player_banned_pre(const id) {
	if (task_exists(id + TASK_DEMO)) {
		remove_task(id + TASK_DEMO);
	}

	new szMess[64], iLen;

	iLen += format(szMess[iLen], sizeof szMess - iLen, "Demo stats: ");

	new bool:isDemo = false;

	for (new i = 0; i < g_iSettings[DEMONUM]; i++) {
		if (g_bNotDemoFiles[id][i]) {
			isDemo = true;
			iLen += format(szMess[iLen], sizeof szMess - iLen, "not (%d) ", i + 1);
		}
	}

	if (!isDemo) {
		iLen += format(szMess[iLen], sizeof szMess - iLen, "All demo done.");
	}

	LogPlayer(id, szMess);
}

public plugin_cfg() {
	g_iVault = nvault_open("demo_recorder");

	if (g_iVault == INVALID_HANDLE)
		log_amx("demo_recorder.amxx: plugin_cfg: can't open file ^"demo_recorder.vault^"!");

	new szLogsDir[128];
	get_localinfo("amxx_logs", szLogsDir, charsmax(szLogsDir));

	add(szLogsDir, charsmax(szLogsDir), "/demo_recorder");

	if (!dir_exists(szLogsDir))
		mkdir(szLogsDir);

	formatex(g_szLogFile, charsmax(g_szLogFile), "%s/%s.log", szLogsDir, LOG_FILE_NAME);
}

public plugin_end() {
	if (g_iVault != INVALID_HANDLE)
		nvault_close(g_iVault);
}

public client_putinserver(id) {
	if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id)) {
		return PLUGIN_HANDLED;
	}

	g_bDemoRecording[id] = false;

	if (g_iVault != INVALID_HANDLE) {
		new szAuthID[32];
		get_user_authid(id, szAuthID, charsmax(szAuthID));

		new szData[16], iTimeStamp;
		if (nvault_lookup(g_iVault, szAuthID, szData, charsmax(szData), iTimeStamp)) {
			new szDemoID[3];
			parse(szData, szDemoID, charsmax(szDemoID));
			g_iCurrentDemoID[id] = str_to_num(szDemoID);
			nvault_remove(g_iVault, szAuthID);
		}
	}

	set_task(5.0, "record_demo", TASK_DEMO + id);

	return PLUGIN_HANDLED;
}

public rgPlayerSpawn(id) {
	if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id) || g_bDemoRecording[id]) {
		return;
	}

	if (task_exists(id + TASK_DEMO)) {
		remove_task(id + TASK_DEMO);
	}

	set_task(5.0, "record_demo", TASK_DEMO + id);
}

public rgDropClient(id) {
	if (g_bDemoRecording[id])
		nvault_set_data(id);

	arrayset(g_bNotDemoFiles[id], 0, sizeof(g_bNotDemoFiles[]));
	g_iCurrentDemoID[id] = 0;
	g_iPlayer[id] = 0;
	g_bDemoRecording[id] = false;

	if (task_exists(id + TASK_DEMO)) {
		remove_task(id + TASK_DEMO);
	}
}

public server_changelevel() {
	for (new id = 1; id <= MaxClients; id++) {
		if (is_user_connected(id)) {
			ClientCmd(id, "stop");
		}
	}
}

public rgServerDeactivate() {
	for (new id = 1; id <= MaxClients; id++) {
		if (is_user_connected(id)) {
			ClientCmd(id, "stop");
		}
	}
}

public record_demo(idtask) {
	new id = idtask - TASK_DEMO;

	if (!is_user_connected(id)) {
		return;
	}
	
	g_iCurrentDemoID[id]++;
	
	if (g_iCurrentDemoID[id] > g_iSettings[DEMONUM])
		g_iCurrentDemoID[id] = 1;

	nvault_set_data(id);

	new szDemoName[32];
	formatex(szDemoName, charsmax(szDemoName), "%s_%d.dem", g_iSettings[DEMONAME], g_iCurrentDemoID[id])

	ClientCmd(id, "stop;record %s", szDemoName);

	g_bDemoRecording[id] = true;

	set_task(3.0, "chat_info", TASK_CHAT + id);
}

public chat_info(idtask) {
	new id = idtask - TASK_CHAT;

	new szDemoName[32];
	formatex(szDemoName, charsmax(szDemoName), "%s_%d.dem", g_iSettings[DEMONAME], g_iCurrentDemoID[id])

	new szTime[32];
	get_time("%m/%d/%Y - %H:%M:%S", szTime, charsmax(szTime));
	client_print_color(id, print_team_blue, "%L", id, "DEMO_RECORD", g_iSettings[DEMOPREFIX], szDemoName, szTime);
}

public nvault_set_data(id) {
	if (g_iVault != INVALID_HANDLE) {
		new szAuthID[32];
		get_user_authid(id, szAuthID, charsmax(szAuthID));

		new szData[16];
		formatex(szData, charsmax(szData), "^"%d^"", g_iCurrentDemoID[id]);

		nvault_set(g_iVault, szAuthID, szData);
	}
}

ClientCmd(id, szCmd[], any: ...) {
	static szCmdFormatted[128];
	vformat(szCmdFormatted, charsmax(szCmdFormatted), szCmd, 3);
	message_begin(MSG_ONE, SVC_DIRECTOR, _, id);
	write_byte(strlen(szCmdFormatted) + 2);
	write_byte(10);
	write_string(szCmdFormatted);
	message_end();
}

stock LogPlayer(id, szFmt[], any: ...) {
	new fp = fopen(g_szLogFile, "at");

	if (fp) {
		new szTime[22], szName[MAX_NAME_LENGTH], szAuthID[32], szIP[21];

		get_time("%m/%d/%Y - %H:%M:%S", szTime, charsmax(szTime));
		get_user_name(id, szName, MAX_NAME_LENGTH - 1);
		get_user_authid(id, szAuthID, charsmax(szAuthID));
		get_user_ip(id, szIP, charsmax(szIP), 1);

		fprintf(fp, "+---^n| L %s: %s<%s><%s> %s^n+---^n^n", szTime, szName, szAuthID, szIP, szFmt);
		fclose(fp);
	}
	else
		log_amx("demo_recorder.amxx: LogPlayer():: can't open file ^"%s^"!", g_szLogFile);
}