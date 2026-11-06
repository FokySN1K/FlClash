package com.follow.clash.plugins

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.ContextCompat.getSystemService
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.net.toUri
import androidx.core.view.OnApplyWindowInsetsListener
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.follow.clash.R
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.common.PendingCallback
import com.follow.clash.common.QuickAction
import com.follow.clash.common.quickIntent
import com.follow.clash.common.registerReceiverCompat
import com.follow.clash.common.shortcutId
import com.follow.clash.getPackageIconPath
import com.follow.clash.packages.PackageResolver
import com.follow.clash.showToast
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class AppPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private var activity: Activity? = null

    private var activityBinding: ActivityPluginBinding? = null

    private val activityResultListener =
        PluginRegistry.ActivityResultListener(::onActivityResult)

    private val permissionsResultListener =
        PluginRegistry.RequestPermissionsResultListener(::onRequestPermissionsResultListener)

    private lateinit var channel: MethodChannel

    private lateinit var scope: CoroutineScope

    private val vpnPrepareCallback = PendingCallback<Boolean>()

    private val requestNotificationCallback = PendingCallback<Boolean>()

    private val requestInstalledAppsCallback = PendingCallback<Boolean>()

    private val requestLocalNetworkCallback = PendingCallback<Boolean>()

    private var isRequestingNotificationPermission = false

    private var isRequestingLocalNetworkPermission = false

    private var skipLocalNetworkPermissionRequest = false

    private val gson = Gson()

    private val packageResolver by lazy {
        PackageResolver(
            GlobalState.application.packageManager,
            GlobalState.application.packageName,
        )
    }

    private var packageChangeContext: Context? = null

    private var installResultContext: Context? = null

    // The installer answers a commit through this receiver with its result.
    private val installResultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            val status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE,
            )
            when (status) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    val confirmation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }
                    if (confirmation != null) {
                        confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        (activity ?: GlobalState.application).startActivity(confirmation)
                    }
                }

                PackageInstaller.STATUS_SUCCESS -> GlobalState.log("Update installed")

                else -> GlobalState.log(
                    "Update failed: ${
                        intent?.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    }",
                )
            }
        }
    }

    private val packageChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null || intent.data?.schemeSpecificPart == GlobalState.application.packageName) {
                return
            }
            val addedByUpdate = intent.action == Intent.ACTION_PACKAGE_ADDED &&
                intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
            if (addedByUpdate) {
                return
            }
            packageResolver.invalidate()
            channel.invokeMethod("packagesChanged", null)
        }
    }

    private var skipNotificationPermissionRequest = false

    @Suppress("DEPRECATION")
    private val isTelevision by lazy {
        val packageManager = GlobalState.application.packageManager
        packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private var floatingIme = false

    // A TV keyboard floats over the app and reports a zero-height IME inset.
    private val imeInsetsListener = OnApplyWindowInsetsListener { view, insets ->
        val ime = WindowInsetsCompat.Type.ime()
        reportFloatingIme(insets.isVisible(ime) && insets.getInsets(ime).bottom == 0)
        ViewCompat.onApplyWindowInsets(view, insets)
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * The permission and consent hops below touch the Activity — starting an
     * activity for result, raising a permission prompt — and read the state that
     * tracks whether one is already up. Their callers are coroutines on
     * [Dispatchers.Default], while the answers come back on the main thread
     * through the ActivityAware listeners, so main is the one thread both ends
     * can agree on. A plain main-looper post rather than the plugin scope: the
     * scope is cancelled when the engine detaches, and a request dropped there
     * would leave its caller waiting for a callback that can no longer run.
     */
    private fun onMainThread(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "moveTaskToBack" -> {
                activity?.moveTaskToBack(true)
                result.success(true)
            }

            "updateExcludeFromRecents" -> {
                val value = call.argument<Boolean>("value")
                updateExcludeFromRecents(value)
                result.success(true)
            }

            "initShortcuts" -> {
                val labels = shortcutLabels(call.arguments)
                if (labels == null) {
                    result.error(
                        "INVALID_ARGUMENT",
                        "Shortcut labels must map every quick action to a string",
                        null,
                    )
                } else {
                    initShortcuts(labels)
                    result.success(true)
                }
            }

            "getPackages" -> reply(result) {
                gson.toJson(packageResolver.installedPackages)
            }

            "getChinaPackageNames" -> reply(result) {
                gson.toJson(packageResolver.getChinaPackageNames())
            }

            "isInstalledAppsPermissionGranted" -> reply(result) {
                packageResolver.hasInstalledAppsPermission()
            }

            "requestInstalledAppsPermission" -> {
                requestInstalledAppsPermission { granted -> result.success(granted) }
            }

            "requestLocalNetworkPermission" -> {
                requestLocalNetworkPermission { granted -> result.success(granted) }
            }

            "getPackageIcon" -> {
                handleGetPackageIcon(call, result)
            }

            "tip" -> {
                val message = call.argument<String>("message")
                GlobalState.application.showToast(message)
                result.success(true)
            }

            "openAppSettings" -> {
                result.success(openAppSettings())
            }

            "getLastExitInfo" -> reply(result) {
                GlobalState.lastExitInfo()
            }

            "installApk" -> {
                val path = call.argument<String>("path")
                val file = path?.let(::File)
                if (file == null || !file.isFile) {
                    result.error("INVALID_ARGUMENT", "No update archive at $path", null)
                } else {
                    installApk(file, result)
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun handleGetPackageIcon(call: MethodCall, result: Result) = reply(result) {
        val packageName = call.argument<String>("packageName") ?: ""
        GlobalState.application.packageManager.getPackageIconPath(packageName)
    }

    // The APK is streamed into a session this process feeds: no file URI and no
    // storage permission, and the system still shows its own confirmation.
    private fun installApk(file: File, result: Result) = onMainThread {
        val activity = activity
        if (activity == null) {
            result.success(false)
            return@onMainThread
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            result.success(openInstallPermissionSettings(activity))
            return@onMainThread
        }
        result.success(commitInstallSession(activity, file))
    }

    private fun openInstallPermissionSettings(activity: Activity): Boolean = runCatching {
        activity.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = "package:${GlobalState.application.packageName}".toUri()
            },
        )
    }.isSuccess

    private fun commitInstallSession(activity: Activity, file: File): Boolean = runCatching {
        val installer = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            setAppPackageName(activity.packageName)
        }
        val session = installer.openSession(installer.createSession(params))
        try {
            session.openWrite("base.apk", 0, file.length()).use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
                session.fsync(output)
            }
            val intent = Intent(ACTION_INSTALL_COMMIT).setPackage(activity.packageName)
            val pending = PendingIntent.getBroadcast(
                GlobalState.application,
                INSTALL_COMMIT_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            session.commit(pending.intentSender)
        } finally {
            session.close()
        }
    }.onFailure { error ->
        GlobalState.log("Unable to install the update: $error")
    }.isSuccess

    // A throw inside the plugin scope has no handler and ends the process;
    // the Dart caller gets a PlatformException to handle instead.
    private fun reply(result: Result, block: suspend () -> Any?) {
        scope.launch(Dispatchers.IO) {
            try {
                result.success(block())
            } catch (error: Exception) {
                GlobalState.log("Platform call failed: $error")
                result.error("PLATFORM_ERROR", error.toString(), null)
            }
        }
    }

    private fun shortcutLabels(arguments: Any?): Map<QuickAction, String>? {
        val map = arguments as? Map<*, *> ?: return null
        return QuickAction.entries.associateWith { action ->
            map[action.shortcutId] as? String ?: return null
        }
    }

    private fun initShortcuts(labels: Map<QuickAction, String>) {
        val shortcuts = SHORTCUT_ORDER.mapIndexed { rank, action ->
            with(ShortcutInfoCompat.Builder(GlobalState.application, action.shortcutId)) {
                setShortLabel(labels.getValue(action))
                setIcon(IconCompat.createWithResource(GlobalState.application, action.shortcutIcon))
                setIntent(action.quickIntent)
                setRank(rank)
                build()
            }
        }
        ShortcutManagerCompat.setDynamicShortcuts(GlobalState.application, shortcuts)
    }

    // Plain circles, not adaptive icons: an adaptive shortcut icon takes the
    // launcher's own mask, which is a square on many devices.
    private val QuickAction.shortcutIcon: Int
        get() = when (this) {
            QuickAction.START -> R.drawable.ic_shortcut_start
            QuickAction.STOP -> R.drawable.ic_shortcut_stop
            QuickAction.TOGGLE -> R.drawable.ic_shortcut_toggle
        }

    private fun openAppSettings(): Boolean {
        val activity = activity ?: return false
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = "package:${GlobalState.application.packageName}".toUri()
            }
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun updateExcludeFromRecents(value: Boolean?) {
        val taskId = activity?.taskId ?: return
        val am = getSystemService(GlobalState.application, ActivityManager::class.java)
        val task = am?.appTasks?.firstOrNull {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.taskInfo?.taskId == taskId
            } else {
                it.taskInfo?.id == taskId
            }
        }
        task?.setExcludeFromRecents(value ?: false)
    }

    fun requestNotificationPermission(callback: (Boolean) -> Unit) = onMainThread {
        requestNotificationCallback.replace(callback, supersededValue = false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permission = ContextCompat.checkSelfPermission(
                GlobalState.application,
                Manifest.permission.POST_NOTIFICATIONS,
            )
            if (permission == PackageManager.PERMISSION_GRANTED || skipNotificationPermissionRequest) {
                invokeRequestNotificationCallback(true)
                return@onMainThread
            }
            if (isRequestingNotificationPermission) {
                return@onMainThread
            }
            isRequestingNotificationPermission = true
            activity?.let {
                ActivityCompat.requestPermissions(
                    it,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE,
                )
            } ?: invokeRequestNotificationCallback(true)
            return@onMainThread
        }
        invokeRequestNotificationCallback(true)
    }

    private fun invokeRequestNotificationCallback(shouldStart: Boolean) {
        isRequestingNotificationPermission = false
        requestNotificationCallback.resolve(shouldStart)
    }

    fun requestLocalNetworkPermission(callback: (Boolean) -> Unit) = onMainThread {
        requestLocalNetworkCallback.replace(callback, supersededValue = false)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.CINNAMON_BUN || hasLocalNetworkPermission()) {
            invokeRequestLocalNetworkCallback(true)
            return@onMainThread
        }
        if (skipLocalNetworkPermissionRequest) {
            invokeRequestLocalNetworkCallback(false)
            return@onMainThread
        }
        if (isRequestingLocalNetworkPermission) {
            return@onMainThread
        }
        val activity = activity
        if (activity == null) {
            invokeRequestLocalNetworkCallback(false)
            return@onMainThread
        }
        isRequestingLocalNetworkPermission = true
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.ACCESS_LOCAL_NETWORK),
            LOCAL_NETWORK_PERMISSION_REQUEST_CODE,
        )
    }

    private fun hasLocalNetworkPermission(): Boolean = ContextCompat.checkSelfPermission(
        GlobalState.application,
        Manifest.permission.ACCESS_LOCAL_NETWORK,
    ) == PackageManager.PERMISSION_GRANTED

    private fun invokeRequestLocalNetworkCallback(granted: Boolean) {
        isRequestingLocalNetworkPermission = false
        requestLocalNetworkCallback.resolve(granted)
    }

    private fun requestInstalledAppsPermission(callback: (Boolean) -> Unit) = onMainThread {
        requestInstalledAppsCallback.replace(callback, supersededValue = false)
        val activity = activity
        if (packageResolver.hasInstalledAppsPermission()) {
            invokeRequestInstalledAppsCallback(true)
            return@onMainThread
        }
        if (activity == null) {
            invokeRequestInstalledAppsCallback(false)
            return@onMainThread
        }
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(PackageResolver.GET_INSTALLED_APPS),
            INSTALLED_APPS_PERMISSION_REQUEST_CODE,
        )
    }

    private fun invokeRequestInstalledAppsCallback(granted: Boolean) {
        if (granted) {
            packageResolver.invalidate()
        }
        requestInstalledAppsCallback.resolve(granted)
    }

    fun prepareVpn(needPrepare: Boolean, callback: (Boolean) -> Unit) = onMainThread {
        vpnPrepareCallback.replace(callback, supersededValue = false)
        if (!needPrepare) {
            invokeVpnPrepareCallback(true)
            return@onMainThread
        }
        val intent = VpnService.prepare(GlobalState.application)
        if (intent != null) {
            val activity = activity
            if (activity == null) {
                invokeVpnPrepareCallback(false)
            } else {
                @Suppress("DEPRECATION")
                activity.startActivityForResult(intent, VPN_PERMISSION_REQUEST_CODE)
            }
            return@onMainThread
        }
        invokeVpnPrepareCallback(true)
    }

    // Posted rather than run where the cancellation lands, so it stays ordered
    // behind the prepareVpn that installed the callback it is cancelling.
    fun cancelVpnPreparation(callback: (Boolean) -> Unit) = onMainThread {
        vpnPrepareCallback.cancel(callback)
    }

    private fun invokeVpnPrepareCallback(granted: Boolean) {
        vpnPrepareCallback.resolve(granted)
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        channel =
            MethodChannel(flutterPluginBinding.binaryMessenger, "${Components.PACKAGE_NAME}/app")
        channel.setMethodCallHandler(this)
        watchPackageChanges(flutterPluginBinding.applicationContext)
        watchInstallResult(flutterPluginBinding.applicationContext)
    }

    private fun watchInstallResult(context: Context) {
        context.registerReceiverCompat(
            installResultReceiver,
            IntentFilter(ACTION_INSTALL_COMMIT),
        )
        installResultContext = context
    }

    private fun watchPackageChanges(context: Context) {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addAction(Intent.ACTION_PACKAGE_FULLY_REMOVED)
            addDataScheme("package")
        }
        context.registerReceiverCompat(packageChangeReceiver, filter)
        packageChangeContext = context
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        packageChangeContext?.unregisterReceiver(packageChangeReceiver)
        packageChangeContext = null
        installResultContext?.unregisterReceiver(installResultReceiver)
        installResultContext = null
        channel.setMethodCallHandler(null)
        scope.cancel()
        invokeVpnPrepareCallback(false)
        invokeRequestNotificationCallback(false)
        invokeRequestLocalNetworkCallback(false)
        invokeRequestInstalledAppsCallback(false)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachToActivity(binding)
    }

    private fun attachToActivity(binding: ActivityPluginBinding) {
        detachFromActivity()
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
        binding.addRequestPermissionsResultListener(permissionsResultListener)
        if (isTelevision) {
            ViewCompat.setOnApplyWindowInsetsListener(
                binding.activity.window.decorView,
                imeInsetsListener,
            )
        }
    }

    private fun detachFromActivity() {
        if (isTelevision) {
            activity?.window?.decorView?.let {
                ViewCompat.setOnApplyWindowInsetsListener(it, null)
            }
            reportFloatingIme(false)
        }
        activity = null
        val binding = activityBinding ?: return
        activityBinding = null
        binding.removeActivityResultListener(activityResultListener)
        binding.removeRequestPermissionsResultListener(permissionsResultListener)
    }

    private fun reportFloatingIme(floating: Boolean) {
        if (floating == floatingIme) {
            return
        }
        floatingIme = floating
        channel.invokeMethod("floatingImeChanged", floating)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        channel.invokeMethod("exit", null)
        detachFromActivity()
        invokeVpnPrepareCallback(false)
        invokeRequestNotificationCallback(false)
        invokeRequestLocalNetworkCallback(false)
        invokeRequestInstalledAppsCallback(false)
    }

    private fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) {
            return false
        }
        invokeVpnPrepareCallback(resultCode == Activity.RESULT_OK)
        return true
    }

    private fun onRequestPermissionsResultListener(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ): Boolean = when (requestCode) {
        NOTIFICATION_PERMISSION_REQUEST_CODE -> {
            skipNotificationPermissionRequest = true
            invokeRequestNotificationCallback(true)
            true
        }

        INSTALLED_APPS_PERMISSION_REQUEST_CODE -> {
            invokeRequestInstalledAppsCallback(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED,
            )
            true
        }

        LOCAL_NETWORK_PERMISSION_REQUEST_CODE -> {
            skipLocalNetworkPermissionRequest = true
            invokeRequestLocalNetworkCallback(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED,
            )
            true
        }

        else -> false
    }

    private companion object {
        val SHORTCUT_ORDER = listOf(QuickAction.START, QuickAction.STOP, QuickAction.TOGGLE)
        const val VPN_PERMISSION_REQUEST_CODE = 1001
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1002
        const val INSTALLED_APPS_PERMISSION_REQUEST_CODE = 1003
        const val LOCAL_NETWORK_PERMISSION_REQUEST_CODE = 1004
        const val INSTALL_COMMIT_REQUEST_CODE = 1005
        const val ACTION_INSTALL_COMMIT = "com.follow.clash.INSTALL_COMMIT"
    }
}
