package com.shaunkleyn.service_keeper;

import rikka.shizuku.Shizuku;
import rikka.shizuku.ShizukuRemoteProcess;

public class ShizukuHelper {
    public static ShizukuRemoteProcess newProcess(String[] cmd, String[] env, String dir) throws Exception {
        return Shizuku.newProcess(cmd, env, dir);
    }
}
