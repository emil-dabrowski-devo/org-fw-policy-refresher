import googleapiclient.discovery
from google.cloud import logging
import requests
import time
import json
import os
import netaddr

#env params
project_id = os.environ.get('PROJECT_ID')
service_account = os.environ.get('SERVICE_ACCOUNT')
org_policy_id = os.environ.get('ORG_POLICY_ID')
rule_id = os.environ.get('RULE_ID')
goog_url= os.environ.get('GOOG_URL')
cloud_url= os.environ.get('CLOUD_URL')
auth_key = os.environ.get('AUTH_KEY')
svc_url = os.environ.get('SVC_URL')


#logging to stackdriver (global -> update-org-fw-rule)
logging_client = logging.Client(project=project_id)
def write_log(message, severity, type="text"):
    global logging_client
    log_name = "update-org-fw-rule"
    logger = logging_client.logger(log_name)
    if type == "text":
        logger.log_text(message, severity=severity)
    elif type == "json":
        logger.log_struct(message)
    else:
        logger.log_text("not proper error structure", severity=severity)

#read data from public urls
def read_url(url):
   try:
      s = requests.get(url)
      return json.loads(s.content)
   except urllib.error.HTTPError:
      write_log("Invalid HTTP response from {0}".format(url), "ERROR")
      return {}
   except json.decoder.JSONDecodeError:
      write_log("Could not parse HTTP response from {0}".format(url), "ERROR")
      return {}

#run cidr getting process
def get_new_cidrs():
    global goog_url
    global cloud_url
    goog_json=read_url(goog_url)
    cloud_json=read_url(cloud_url)
    if goog_json and cloud_json:
        goog_cidrs = netaddr.IPSet()
        for e in goog_json['prefixes']:
            if e.get('ipv4Prefix'):
                goog_cidrs.add(e.get('ipv4Prefix'))
        cloud_cidrs = netaddr.IPSet()
        for e in cloud_json['prefixes']:
            if e.get('ipv4Prefix'):
                cloud_cidrs.add(e.get('ipv4Prefix'))
        list = []
        for i in goog_cidrs.difference(cloud_cidrs).iter_cidrs():
            list.append(str(i))
    return(list)

#get signed jwt
def get_jwt():
    global credenials
    global project_id
    global service_account
    now = int(time.time())
    expires = now + 240
    payload = {
        'iss': service_account,
        'iat': now,
        'exp': expires,
        'sub': service_account,
        'aud': 'https://compute.googleapis.com/'
    }
    body = {'payload': json.dumps(payload)}
    name = 'projects/{0}/serviceAccounts/{1}'.format(
        project_id, service_account)

    # Perform the GCP API call
    iam = googleapiclient.discovery.build(
        'iam',
        'v1',
        cache_discovery=False
    )
    request = iam.projects().serviceAccounts().signJwt(
        name=name,
        body=body
        )
    resp = request.execute()
    jwt = resp['signedJwt']
    return (jwt)

#get actual firewall rule
def get_fw_rule(signed_jwt, url):
    headers = {
        'Authorization': 'Bearer {}'.format(signed_jwt),
        'content-type': 'application/json'
    }
    response = requests.get(url, headers=headers)
    return(response.content)

#update firewall rule
def update_fw_rule(signed_jwt, body):
    global org_policy_id
    global rule_id
    global svc_url
    url = svc_url+org_policy_id+'/patchRule/?priority='+rule_id
    headers = {
        'Authorization': 'Bearer {}'.format(signed_jwt),
        'content-type': 'application/json'
    }

    response = requests.post(url, json=body, headers=headers)
    return(response)

#compare cidrs
def run_comparison():
    global org_policy_id
    global rule_id
    global svc_url
    signed_jwt = get_jwt()
    url = svc_url+org_policy_id+'/getRule?priority='+rule_id
    response = get_fw_rule(signed_jwt,url)
    resp_dict = json.loads(response)
    current_ip_ranges = resp_dict['match']['config']['destIpRanges']
    new_ip_ranges = get_new_cidrs()
    compare_1 = list(set(current_ip_ranges) - set(new_ip_ranges))
    compare_2 = list(set(new_ip_ranges) - set(current_ip_ranges))
    if len(compare_1) > 0 or len(compare_2) > 0:
        resp_dict['match']['config']['destIpRanges'] = new_ip_ranges[:-1]
        result = update_fw_rule(signed_jwt, resp_dict)
        get_data = result.json()
        write_log(get_data['status'], "INFO")
    else:
        write_log("Firewall rule is up to date", "INFO")
        
#start app
def init_app(request):
    global auth_key
    request_json = request.get_json()
    try:
        auth_checker = request_json['message']
        if auth_checker == auth_key:
            print("run comparison")
            run_comparison()
            return ('200')
        else:
            write_log("not authorized", "CRITICAL")
            return ('403')
    except Exception as e:
        write_log(e,"ERROR", "json")
        return ("exception error")
