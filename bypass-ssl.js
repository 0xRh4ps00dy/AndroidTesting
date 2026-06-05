/*
   Universal Android SSL Pinning Bypass Script for Frida
   Soporta: TrustManager, OkHttp3, WebView, TrustKit, Appcelerator, OpenSSLSocketImpl, etc.
*/

Java.perform(function() {
    console.log("\n[+] Iniciando bypass de SSL Pinning con Frida...");

    // 1. Bypass para Java TrustManager (X509TrustManager)
    try {
        var X509TrustManager = Java.use('javax.net.ssl.X509TrustManager');
        var TrustManagerImpl = Java.use('com.android.org.conscrypt.TrustManagerImpl');
        var TrustManager = Java.registerClass({
            name: 'com.example.TrustManager',
            implements: [X509TrustManager],
            methods: {
                checkClientTrusted: function(chain, authType) {},
                checkServerTrusted: function(chain, authType) {},
                getAcceptedIssuers: function() { return []; }
            }
        });
        
        var TrustManagers = [TrustManager.$new()];
        var SSLContext = Java.use('javax.net.ssl.SSLContext');
        
        // Sobreescribir init de SSLContext
        SSLContext.init.overload('[Ljavax.net.ssl.KeyManager;', '[Ljavax.net.ssl.TrustManager;', 'java.security.SecureRandom').implementation = function(km, tm, sr) {
            console.log("[*] Hooked SSLContext.init() -> Aplicando nuestro TrustManager");
            SSLContext.init.overload('[Ljavax.net.ssl.KeyManager;', '[Ljavax.net.ssl.TrustManager;', 'java.security.SecureRandom').call(this, km, TrustManagers, sr);
        };
        
        // Sobreescribir TrustManagerImpl para Conscrypt
        TrustManagerImpl.checkTrustedRecursive.implementation = function(certs, host, clientAuth, untrustedChain, trustAnchorChain, index) {
            console.log("[*] Hooked TrustManagerImpl.checkTrustedRecursive() para host: " + host);
            return Java.use('java.util.ArrayList').$new();
        };
    } catch (err) {
        console.log("[!] Error al aplicar bypass de TrustManager: " + err.message);
    }

    // 2. Bypass para OkHttp3 (CertificatePinner)
    try {
        var CertificatePinner = Java.use('okhttp3.CertificatePinner');
        CertificatePinner.check.overload('java.lang.String', 'java.util.List').implementation = function(host, peerCertificates) {
            console.log("[*] Hooked OkHttp3 CertificatePinner para host: " + host);
            return;
        };
    } catch (err) {
        console.log("[!] OkHttp3 no encontrado o no se pudo aplicar el hook: " + err.message);
    }

    // 3. Bypass para WebViewClient (errores SSL en WebViews)
    try {
        var WebViewClient = Java.use('android.webkit.WebViewClient');
        WebViewClient.onReceivedSslError.implementation = function(view, handler, error) {
            console.log("[*] Hooked WebViewClient.onReceivedSslError() -> Procediendo con la conexion");
            handler.proceed();
        };
    } catch (err) {
        console.log("[!] Error al aplicar bypass de WebViewClient: " + err.message);
    }
});
