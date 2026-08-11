To optimize your Veeam backup performance, you need to test both TCP (for general throughput and control) and UDP (to find the maximum line rate and packet loss). Veeam heavily relies on concurrent streams and large block sizes, so your iPerf tests should mimic this behavior.
Here are the optimized scripts you can use.
## 🌐 Test Topology Assumption

* Veeam Proxy / Source: Running the iPerf Client.
* Veeam Repository / Destination: Running the iPerf Server.

------------------------------
## 1. Setup the iPerf Server (Repository Side)
Run this command on your backup repository machine. It will keep listening for incoming test connections.

# -s starts server mode, -p specifies the port (default is 5201)
iperf3 -s -p 5201

Note: Ensure your firewall allows traffic through TCP/UDP port 5201 between your proxy and repository.
------------------------------
## 2. TCP Throughput Script (Simulating Veeam Data Streams)
Veeam transfers data using multiple concurrent TCP connections. This script simulates 8 parallel streams over a 60-second window to test maximum bandwidth and stability.

# Run this on your Veeam Proxy (Client)
iperf3 -c <REPOSITORY_IP> -p 5201 -t 60 -P 8 -f m

Parameter Breakdown:

* -c <REPOSITORY_IP>: Connects to your Veeam repository IP address.
* -t 60: Runs the test for 60 seconds to get a reliable average throughput.
* -P 8: Spawns 8 parallel client streams (mimics Veeam concurrent task processing).
* -f m: Displays the results in Megabits per second (Mbps).

------------------------------
## 3. UDP Packet Loss Script (Simulating Network Saturation)
Veeam backups can fail or slow down drastically if there is packet loss. UDP testing forces traffic at a specific bandwidth limit to see where your network begins dropping packets.

# Run this on your Veeam Proxy (Client) to test a 1 Gbps link
iperf3 -c <REPOSITORY_IP> -p 5201 -u -b 1G -t 30

Parameter Breakdown:

* -u: Switches iPerf to UDP mode.
* -b 1G: Sets the target bandwidth to 1 Gbps (adjust this to match your network speed, e.g., 10G for 10 Gbps links).
* What to look for: Check the final summary for Jitter and Lost/Total Packets. Packet loss should ideally be 0%. Anything above 0.5% will severely degrade Veeam performance.

------------------------------
## 💡 Veeam Tuning Best Practices

* Match MTU Sizes: If your Veeam environment uses Jumbo Frames, append --set-mss 8960 to your TCP script to ensure iPerf tests the larger payload sizes.
* Bi-directional Testing: For replication jobs, reverse the direction by adding the -R flag to the client script to test download/ingress speeds.
