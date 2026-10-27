"""Record an observed idle browser for explicit later CLI admission; never close it."""
from common import *
from process_inventory import idle_editor_fingerprint,require_idle_shape
import argparse
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--pid',type=int,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args();need(not args.output.exists(),'Preserve an existing fingerprint');actual=idle_editor_fingerprint(args.pid);require_idle_shape(actual);args.output.parent.mkdir(parents=True,exist_ok=True);write(args.output,{'scope':'EXPLICIT_IDLE_EDITOR_IDENTITY_ONLY','exact_fingerprint':actual,'raw_commandline_included':False,'external_process_modified':False});print(json.dumps(actual))
if __name__=='__main__':main()
