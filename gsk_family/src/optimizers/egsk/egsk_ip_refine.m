function [x, f, current_eval] = egsk_ip_refine(bestx, f, current_eval, problem, Max_FES)
%EGSK_IP_REFINE eGSK IP local refinement with fmincon (SQP).
%
%   [x, f, current_eval] = egsk_ip_refine(bestx, f, current_eval, problem, Max_FES)
%
% Transcribed verbatim from:
%   historical source: egsk/egsk/finaleGSK2023/IP.m
%
% Runs fmincon SQP from the 1 x D row bestx(1,:) with a budget of
% ceil(0.002*Max_FES) evaluations. If the result has a strictly lower
% fitness, returns it as x and f; otherwise returns bestx and f unchanged.
% current_eval grows by fmincon's funcCount.
%
% Reference signature:
%   [x,f,current_eval,g,run_funcvals] = IP(bestx,f,current_eval,I_fno, ...
%                                          Max_FES,xmin,xmax,g,run_funcvals)
% IP.m returns g and run_funcvals unchanged, so they are dropped here. The
% only adaptation: the hard-coded objective
% fmincon(@cec17_func, bestx(1,:)', ..., I_fno) becomes problem.evaluate on
% the row form of the column iterate. Bounds are problem.lb/problem.ub (the
% reference passes the rows lu(1,:)/lu(2,:) with a column x0; fmincon
% accepts either orientation).
%
% The caller checks that the Optimization Toolbox is available; this
% function assumes fmincon exists. The legacy optimset settings (including
% 'UseParallel','never') are kept exactly as in the reference and verified
% to work with fmincon on R2025b.

IP_FE = ceil(2.0000e-003 * Max_FES); % fmincon evaluation budget
options = optimset('Display', 'off', 'algorithm', 'sqp', ...
    'UseParallel', 'never', 'MaxFunEvals', IP_FE);

objective = @(z) problem.evaluate(z(:).'); % column iterate -> 1xD row -> scalar fitness

[Xsqp, FUN, ~, details] = fmincon(objective, bestx(1, :)', [], [], [], [], problem.lb, problem.ub, [], options);

%% Keep the fmincon result only if it improves the fitness
if (f - FUN) > 0
    f = FUN;
    x = bestx;
    x(1, :) = Xsqp; % reference assigns the column Xsqp into the row x(1,:)
else
    x = bestx;
end
%% Add fmincon's evaluations to the counter
current_eval = current_eval + details.funcCount;
end
