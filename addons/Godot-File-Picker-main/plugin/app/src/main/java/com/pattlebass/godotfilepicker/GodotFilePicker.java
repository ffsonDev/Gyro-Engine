package com.pattlebass.godotfilepicker;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashSet;
import java.util.Set;

public class GodotFilePicker extends GodotPlugin {
	private static final int REQUEST_PICK = 1001;
	private static final int REQUEST_SAVE = 1002;
	private String pendingSourcePath = "";

	public GodotFilePicker(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "GodotFilePicker";
	}

	@Override
	public Set<SignalInfo> getPluginSignals() {
		Set<SignalInfo> signals = new HashSet<>();
		signals.add(new SignalInfo("file_picked", String.class, String.class));
		signals.add(new SignalInfo("file_saved", Boolean.class, String.class));
		return signals;
	}

	@UsedByGodot
	public void openFilePicker(final String mimeType) {
		final Activity activity = getActivity();
		if (activity == null) {
			return;
		}
		activity.runOnUiThread(new Runnable() {
			@Override
			public void run() {
				Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
				intent.addCategory(Intent.CATEGORY_OPENABLE);
				intent.setType(mimeType);
				activity.startActivityForResult(intent, REQUEST_PICK);
			}
		});
	}

	@UsedByGodot
	public void saveFileAs(final String sourcePath, final String mimeType, final String title) {
		final Activity activity = getActivity();
		if (activity == null) {
			return;
		}
		pendingSourcePath = sourcePath;
		activity.runOnUiThread(new Runnable() {
			@Override
			public void run() {
				Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
				intent.addCategory(Intent.CATEGORY_OPENABLE);
				intent.setType(mimeType);
				intent.putExtra(Intent.EXTRA_TITLE, title);
				activity.startActivityForResult(intent, REQUEST_SAVE);
			}
		});
	}

	@Override
	public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
		if (requestCode == REQUEST_PICK) {
			if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null) {
				Uri uri = data.getData();
				String temp = copyToTemp(uri);
				String mime = "";
				try {
					mime = getActivity().getContentResolver().getType(uri);
				} catch (Exception e) {
				}
				emitSignal("file_picked", temp == null ? "" : temp, mime == null ? "" : mime);
			} else {
				emitSignal("file_picked", "", "");
			}
		} else if (requestCode == REQUEST_SAVE) {
			boolean ok = false;
			String uriString = "";
			if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null && !pendingSourcePath.isEmpty()) {
				uriString = data.getData().toString();
				ok = copyToUri(pendingSourcePath, data.getData());
			}
			pendingSourcePath = "";
			emitSignal("file_saved", ok, uriString);
		}
	}

    private String copyToTemp(Uri uri) {
	    try {
		    Activity activity = getActivity();
		    String safe = sanitizeName(queryDisplayName(uri));
		    String prefix = "picked_" + System.currentTimeMillis();
		    File out = safe.isEmpty()
				    ? new File(activity.getCacheDir(), prefix)
				    : new File(activity.getCacheDir(), prefix + "_" + safe);
		    InputStream in = activity.getContentResolver().openInputStream(uri);
		    if (in == null) return null;
		    OutputStream os = new FileOutputStream(out);
		    byte[] buf = new byte[65536];
		    int r;
		    while ((r = in.read(buf)) > 0) { os.write(buf, 0, r); }
		    os.close(); in.close();
		    return out.getAbsolutePath();
	    } catch (Exception e) {
		    return null;
	    }
    }

    private String queryDisplayName(Uri uri) {
	    android.database.Cursor c = null;
	    try {
		    c = getActivity().getContentResolver().query(uri, null, null, null, null);
		    if (c != null && c.moveToFirst()) {
			    int idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
			    if (idx >= 0) return c.getString(idx);
		    }
	    } catch (Exception e) {
	    } finally {
		    if (c != null) c.close();
	    }
	    return null;
    }

    private static String sanitizeName(String n) {
	    if (n == null) return "";
	    StringBuilder sb = new StringBuilder();
	    for (int i = 0; i < n.length(); i++) {
		    char ch = n.charAt(i);
		    if (ch == '/' || ch == '\\' || ch == ':' || ch == '*' || ch == '?'
				    || ch == '"' || ch == '<' || ch == '>' || ch == '|') sb.append('_');
		    else sb.append(ch);
	    }
	    return sb.toString().trim();
    }

	private boolean copyToUri(String sourcePath, Uri uri) {
		try {
			Activity activity = getActivity();
			InputStream in = new FileInputStream(sourcePath);
			OutputStream os = activity.getContentResolver().openOutputStream(uri);
			byte[] buf = new byte[65536];
			int r;
			while ((r = in.read(buf)) > 0) {
				os.write(buf, 0, r);
			}
			os.close();
			in.close();
			return true;
		} catch (Exception e) {
			return false;
		}
	}
}
