import json
import os
import sys

def parse_recon(base_dir):
    report = {
        "domain": base_dir.split('_')[1] if '_' in base_dir else "unknown",
        "web_assets": [],
        "open_services": []
    }

    metadata_path = os.path.join(base_dir, "web/metadata.txt")
    services_path = os.path.join(base_dir, "network/services.txt")

    if os.path.exists(metadata_path):
        with open(metadata_path, "r") as f:
            for line in f:
                parts = line.strip().split(" ")
                report["web_assets"].append({
                    "url": parts[0],
                    "info": " ".join(parts[1:])
                })

    if os.path.exists(services_path):
        with open(services_path, "r") as f:
            for line in f:
                report["open_services"].append(line.strip())

    # Save to reports folder
    json_out = os.path.join(base_dir, "reports/final_report.json")
    txt_out = os.path.join(base_dir, "reports/final_report.txt")

    with open(json_out, "w") as jf:
        json.dump(report, jf, indent=4)

    with open(txt_out, "w") as tf:
        tf.write(f"RECON SUMMARY FOR {report['domain']}\n")
        tf.write("="*30 + "\n\n")
        tf.write(f"Total Web Assets: {len(report['web_assets'])}\n")
        for asset in report["web_assets"]:
            tf.write(f"[+] {asset['url']} | {asset['info']}\n")
        
        tf.write("\nNETWORK SERVICES\n")
        tf.write("-" * 15 + "\n")
        for service in report["open_services"]:
            tf.write(f"[!] {service}\n")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        parse_recon(sys.argv[1])
    else:
        print("Error: No output directory provided to Python script.")
