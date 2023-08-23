import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";

export interface Route53HostedZoneProps {
  alb: cdk.aws_elasticloadbalancingv2.IApplicationLoadBalancer;
}

export class Route53HostedZone extends Construct {
  readonly asg: cdk.aws_autoscaling.AutoScalingGroup;

  constructor(scope: Construct, id: string, props: Route53HostedZoneProps) {
    super(scope, id);

    const hostedZone = new cdk.aws_route53.PublicHostedZone(this, "Default", {
      zoneName: "web.non-97.net",
    });

    new cdk.aws_route53.ARecord(this, "Hoge", {
      zone: hostedZone,
      recordName: `hoge.${hostedZone.zoneName}`,
      target: cdk.aws_route53.RecordTarget.fromAlias(
        new cdk.aws_route53_targets.LoadBalancerTarget(props.alb)
      ),
    });
    new cdk.aws_route53.ARecord(this, "Fuga", {
      zone: hostedZone,
      recordName: `fuga.${hostedZone.zoneName}`,
      target: cdk.aws_route53.RecordTarget.fromAlias(
        new cdk.aws_route53_targets.LoadBalancerTarget(props.alb)
      ),
    });
  }
}
