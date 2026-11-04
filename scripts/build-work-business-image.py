"""Build a compatible candidate from the live image without changing the live container."""
import argparse, hashlib, importlib.util, json, pathlib

ROOT=pathlib.Path(__file__).resolve().parents[1]
BACKEND=ROOT/'后端代码/melhat_server-dev'
spec=importlib.util.spec_from_file_location('patch',BACKEND/'local-dev/wearable-container-patch.py')
patch=importlib.util.module_from_spec(spec);spec.loader.exec_module(patch)

def main(directory):
    directory=pathlib.Path(directory).resolve()
    assert directory.parent==BACKEND/'build' and directory.name.startswith('work-business-')
    manifest=patch.read_json(directory/'release.json'); jar=directory/'fdc-admin.jar'
    assert manifest['unchangedNonTaskEntriesVerified']
    assert hashlib.sha256(jar.read_bytes()).hexdigest()==manifest['jarSha256']
    live=patch.inspect('melhat-backend');assert live['State']['Running']
    running=patch.docker('exec','melhat-backend','sha256sum','/app/fdc-admin.jar').decode().split()[0]
    assert running==manifest['baselineJarSha256'], 'Live JAR changed; rebase candidate first'
    base='melhat-backend:'+directory.name+'-base'; image='melhat-backend:'+directory.name
    patch.docker('tag',live['Image'],base)
    (directory/'Dockerfile').write_text('FROM '+base+'\nCOPY fdc-admin.jar /app/fdc-admin.jar\n',encoding='utf-8')
    (directory/'.dockerignore').write_text('*\n!fdc-admin.jar\n!Dockerfile\n',encoding='utf-8')
    with (directory/'image-build.log').open('wb') as output:
        patch.docker('build','--network','none','-t',image,str(directory),output=output,timeout=300)
    candidate=patch.inspect(image)
    assert candidate['Config']['Entrypoint']==live['Config']['Entrypoint']
    manifest.update(oldImageId=live['Image'],newImageId=live['Image'],oldContainerId=live['Id'],image=image,candidateImageId=candidate['Id'])
    patch.write_json(directory/'release.json',manifest)
    print(json.dumps({'image':image,'candidateImageId':candidate['Id'],'jarSha256':manifest['jarSha256'],'dailyContainerChanged':False}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True);main(parser.parse_args().directory)
