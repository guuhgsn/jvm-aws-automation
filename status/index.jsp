<%@ page import="java.net.InetAddress" %>
<%
    // captura as informacoes do host via Java
    String hostname = InetAddress.getLocalHost().getHostName();
    String ip = InetAddress.getLocalHost().getHostAddress();
    String os = System.getProperty("os.name");

    // captura as informacoes da JVM via Java
    String jvmName = System.getenv("JVM_NAME");
    if (jvmName == null || jvmName.isEmpty()) {
        jvmName = "Unknown";
    }
%>
    <!DOCTYPE html>
    <html>
    <head>
        <title>JVM STATUS - AUTOMATION CENTER</title>
        <style>
            body {
                font-family: 'Courier New', Courier, monospace;
                background-color: #121212;
                color: #00ff00;
                text-align: center;
                margin-top: 10vh;
            }
            .box {
                border: 2px solid #00ff00;
                padding: 20px;
                display: inline-block;
                background-color: #1e1e1e;
                box-shadow: 0 0 15px #00ff00;
            }
            .pixel-art {
                width: 40px;
                height: 40px;
                background-color: #00ff00;
                margin: 20px auto;
                box-shadow: 10px 10px 0 #005500, -10px -10px 0 #00ff00;
                animation: pulse 1s infinite alternate steps(2);
            }
            @keyframes pulse {
                from {
                    transform: scale(1);
                }
                to {
                    transform: scale(1.2);
                }
            }
        </style>
    </head>
    <body>
        <div class="box">
            <h1>[ SERVER ONLINE! ]</h1>
            <div class="pixel-art"></div>
            <hr style="border-color: #00ff00;">
            <p><strong>JVM Name:</strong> 
                <%= jvmName %>
            </p>
            <p><strong>Hostname:</strong>
                <%= hostname %>
            </p>
            <p><strong>IP Interno:</strong>
                <%= ip %>
            </p>
            <p><strong>OS:</strong>
                <%= os %>
            </p>
            <p><strong>Logs path:</strong> /suporteapp</p>
        </div>
    </body>
    </html>